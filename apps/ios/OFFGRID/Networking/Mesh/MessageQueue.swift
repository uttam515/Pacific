import Foundation

public enum MessagePriority: Int, Comparable, Sendable {
    case p0EmergencySOS = 0
    case p1EmergencyAck = 1
    case p2NormalMessage = 2
    case p3Diagnostics = 3

    public static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public struct QueuedMeshItem: Sendable {
    public let operation: OFFGRIDOperation
    public let message: OFFGRIDMessage?
    public let priority: MessagePriority
    public var retryCount: Int
    public var nextAttemptAt: Date
    public var failedPeerIds: Set<String>
    public let enqueuedAt: Date
    public let expiresAt: Date

    public init(
        operation: OFFGRIDOperation,
        message: OFFGRIDMessage?,
        priority: MessagePriority,
        retryCount: Int = 0,
        nextAttemptAt: Date = Date(),
        failedPeerIds: Set<String> = [],
        enqueuedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.operation = operation
        self.message = message
        self.priority = priority
        self.retryCount = retryCount
        self.nextAttemptAt = nextAttemptAt
        self.failedPeerIds = failedPeerIds
        self.enqueuedAt = enqueuedAt
        // Emergency SOS expires in 24 hours; normal messages expire in 7 days
        self.expiresAt = expiresAt ?? (priority == .p0EmergencySOS
            ? enqueuedAt.addingTimeInterval(86400)
            : enqueuedAt.addingTimeInterval(86400 * 7))
    }
}

/// Persistent, priority-aware queue for pending mesh operations with exponential backoff
/// and anti-starvation fair scheduling.
public final class MessageQueue: @unchecked Sendable {
    public static let shared = MessageQueue()

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private let lock = NSRecursiveLock()

    private var inMemoryItems: [String: QueuedMeshItem] = [:]
    private var emergencyProcessedCounter: Int = 0

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadPendingFromPersistence()
    }

    /// Loads uncommitted/pending operations from SQLite on startup or recovery
    public func loadPendingFromPersistence() {
        lock.lock()
        defer { lock.unlock() }

        let pendingOps = operationRepository.getPendingOperations()
        for op in pendingOps {
            guard op.syncStatus == .localOnly || op.syncStatus == .queued || op.syncStatus == .failed else {
                continue
            }

            let msg = messageRepository.getMessage(id: op.entityId)
            let priority: MessagePriority
            if op.entityType == .sos {
                priority = .p0EmergencySOS
            } else {
                priority = .p2NormalMessage
            }

            let item = QueuedMeshItem(
                operation: op,
                message: msg,
                priority: priority,
                retryCount: op.retryCount,
                nextAttemptAt: Date()
            )
            inMemoryItems[op.id.lowercased()] = item
        }
    }

    public func enqueue(
        operation: OFFGRIDOperation,
        message: OFFGRIDMessage?,
        priority: MessagePriority
    ) {
        lock.lock()
        defer { lock.unlock() }

        let item = QueuedMeshItem(
            operation: operation,
            message: message,
            priority: priority,
            retryCount: operation.retryCount
        )
        inMemoryItems[operation.id.lowercased()] = item
    }

    /// Selects the next eligible item according to emergency-first priority with anti-starvation
    public func dequeueNextEligible(excludingPeers: Set<String> = []) -> QueuedMeshItem? {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        pruneExpiredInternal(now: now)

        let eligible = inMemoryItems.values.filter { item in
            item.nextAttemptAt <= now
        }

        guard !eligible.isEmpty else { return nil }

        // Anti-starvation logic:
        // If we've processed 4 consecutive P0/P1 emergency messages, allow 1 P2 normal message
        // to proceed if available, ensuring normal communications don't starve forever.
        let hasNormal = eligible.contains { $0.priority == .p2NormalMessage }

        if emergencyProcessedCounter >= 4 && hasNormal {
            if let normalItem = eligible.filter({ $0.priority == .p2NormalMessage }).min(by: { $0.enqueuedAt < $1.enqueuedAt }) {
                emergencyProcessedCounter = 0
                return normalItem
            }
        }

        // Standard priority ordering: P0 > P1 > P2 > P3, then enqueuedAt
        let sorted = eligible.sorted { left, right in
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.enqueuedAt < right.enqueuedAt
        }

        guard let chosen = sorted.first else { return nil }

        if chosen.priority <= .p1EmergencyAck {
            emergencyProcessedCounter += 1
        } else {
            emergencyProcessedCounter = 0
        }

        return chosen
    }

    /// Records a failed attempt for an operation, backing off exponentially and recording the failed peer
    public func recordAttemptFailure(operationId: String, peerId: String) {
        lock.lock()
        defer { lock.unlock() }

        let key = operationId.lowercased()
        guard var item = inMemoryItems[key] else { return }

        item.retryCount += 1
        item.failedPeerIds.insert(peerId)

        // Exponential backoff: 1.5s * 2^(retries - 1), max 60s
        let delay = min(60.0, 1.5 * pow(2.0, Double(max(0, item.retryCount - 1))))
        item.nextAttemptAt = Date().addingTimeInterval(delay)

        inMemoryItems[key] = item
        operationRepository.incrementRetry(operationId: operationId)
        operationRepository.markStatus(operationId: operationId, status: .queued)
    }

    /// Records delivery success or relay progress, removing item from pending retry
    public func remove(operationId: String) {
        lock.lock()
        defer { lock.unlock() }
        inMemoryItems.removeValue(forKey: operationId.lowercased())
    }

    /// Returns count of pending items in queue
    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryItems.count
    }

    public var allItems: [QueuedMeshItem] {
        lock.lock()
        defer { lock.unlock() }
        return Array(inMemoryItems.values)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        inMemoryItems.removeAll()
        emergencyProcessedCounter = 0
    }

    private func pruneExpiredInternal(now: Date) {
        for (key, item) in inMemoryItems {
            if item.expiresAt < now {
                inMemoryItems.removeValue(forKey: key)
                operationRepository.markStatus(operationId: item.operation.id, status: .failed)
                if let msgId = item.message?.id {
                    messageRepository.updateStatus(id: msgId, status: .failed)
                }
            }
        }
    }
}
