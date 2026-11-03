import Foundation

/// Manages packet and message deduplication across the OFFGRID multi-hop mesh.
/// Backed by SQLite persistence with an in-memory thread-safe cache for low latency.
public final class DeduplicationManager: @unchecked Sendable {
    public static let shared = DeduplicationManager()

    private let database: SQLiteDatabase
    private let lock = NSRecursiveLock()

    // Fast in-memory caches
    private var processedPacketIds = Set<String>()
    private var processedOperationIds = Set<String>()
    private var processedEntityIds = Set<String>()

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
        // Prune expired records on startup
        database.pruneExpiredPackets(now: Date())
    }

    /// Checks if a packet, operation, or entity has already been processed or stored.
    public func isDuplicate(packetId: String, operationId: String, entityId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let packetLower = packetId.lowercased()
        let opLower = operationId.lowercased()
        let entityLower = entityId.lowercased()

        // 1. Fast path: in-memory cache
        if processedPacketIds.contains(packetLower) ||
            processedOperationIds.contains(opLower) ||
            processedEntityIds.contains(entityLower) {
            return true
        }

        // 2. Persistent path: SQLite database
        if database.isPacketProcessed(packetId: packetLower) ||
            database.isOperationProcessed(operationId: opLower) ||
            database.getMessage(byId: entityLower) != nil ||
            database.getOperation(byOperationId: opLower) != nil {
            // Populate fast in-memory cache
            processedPacketIds.insert(packetLower)
            processedOperationIds.insert(opLower)
            processedEntityIds.insert(entityLower)
            return true
        }

        return false
    }

    /// Records a packet, operation, and entity as processed, with persistent backing and expiry.
    public func markProcessed(
        packetId: String,
        operationId: String,
        entityId: String,
        originNodeId: String,
        expiresAt: Date = Date().addingTimeInterval(86400 * 7) // 7 days retention
    ) {
        lock.lock()
        defer { lock.unlock() }

        let packetLower = packetId.lowercased()
        let opLower = operationId.lowercased()
        let entityLower = entityId.lowercased()
        let originLower = originNodeId.lowercased()

        processedPacketIds.insert(packetLower)
        processedOperationIds.insert(opLower)
        processedEntityIds.insert(entityLower)

        database.recordProcessedPacket(
            packetId: packetLower,
            operationId: opLower,
            entityId: entityLower,
            originNodeId: originLower,
            expiresAt: expiresAt
        )
    }

    /// Evicts expired packets from database and fast cache
    public func pruneExpired(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        database.pruneExpiredPackets(now: now)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        processedPacketIds.removeAll()
        processedOperationIds.removeAll()
        processedEntityIds.removeAll()
    }
}
