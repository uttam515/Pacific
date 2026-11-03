import Foundation

public enum RoutingEventType: String, Codable, Sendable {
    case peerDiscovered = "PEER_DISCOVERED"
    case peerConnected = "PEER_CONNECTED"
    case peerDisconnected = "PEER_DISCONNECTED"
    case routeSelected = "ROUTE_SELECTED"
    case alternativeRouteSelected = "ALTERNATIVE_ROUTE_SELECTED"
    case packetForwarded = "PACKET_FORWARDED"
    case forwardingFailed = "FORWARDING_FAILED"
    case ackReceived = "ACK_RECEIVED"
    case ackForwarded = "ACK_FORWARDED"
    case loopPrevented = "LOOP_PREVENTED"
    case emergencyPrioritized = "EMERGENCY_PRIORITIZED"
}

public struct NetworkRoutingEvent: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let eventType: RoutingEventType
    public let messageId: String?
    public let sourceNode: String
    public let targetNode: String?
    public let explanation: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        eventType: RoutingEventType,
        messageId: String? = nil,
        sourceNode: String,
        targetNode: String? = nil,
        explanation: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.messageId = messageId
        self.sourceNode = sourceNode
        self.targetNode = targetNode
        self.explanation = explanation
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Observes network topology, traffic, failures, and generates explainable routing events.
public final class NetworkAnalyzer: @unchecked Sendable {
    public static let shared = NetworkAnalyzer()

    private let database: SQLiteDatabase
    private let lock = NSRecursiveLock()
    private var inMemoryEvents: [NetworkRoutingEvent] = []

    public var onEventLogged: ((NetworkRoutingEvent) -> Void)?

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
        loadPersistedEvents()
    }

    private func loadPersistedEvents() {
        let rows = database.fetchRecentRoutingEvents(limit: 50)
        lock.lock()
        defer { lock.unlock() }
        inMemoryEvents = rows.compactMap { row in
            guard let type = RoutingEventType(rawValue: row.eventType) else { return nil }
            return NetworkRoutingEvent(
                id: row.id,
                timestamp: row.timestamp,
                eventType: type,
                messageId: row.messageId,
                sourceNode: row.sourceNode,
                targetNode: row.targetNode,
                explanation: row.explanation
            )
        }
    }

    /// Logs an observable, explainable routing event
    public func recordEvent(
        type: RoutingEventType,
        messageId: String? = nil,
        sourceNode: String,
        targetNode: String? = nil,
        explanation: String
    ) {
        let event = NetworkRoutingEvent(
            eventType: type,
            messageId: messageId,
            sourceNode: sourceNode,
            targetNode: targetNode,
            explanation: explanation
        )

        lock.lock()
        inMemoryEvents.insert(event, at: 0)
        if inMemoryEvents.count > 100 {
            inMemoryEvents.removeLast()
        }
        lock.unlock()

        database.recordRoutingEvent(
            id: event.id,
            eventType: event.eventType.rawValue,
            messageId: event.messageId,
            sourceNode: event.sourceNode,
            targetNode: event.targetNode,
            explanation: event.explanation
        )

        onEventLogged?(event)
    }

    /// Generates structured AI / rule explainability for route recovery
    public func explainRouteRecovery(
        failedPeer: String,
        chosenPeer: DiscoveredPeer,
        score: RelayScoreBreakdown,
        messageId: String,
        isEmergency: Bool
    ) -> String {
        let urgency = isEmergency ? "Emergency SOS" : "Message"
        return "\(urgency) [\(messageId.prefix(8))] preserved after [\(failedPeer)] disconnected. Selected [\(chosenPeer.displayName)] as alternative relay with score \(String(format: "%.1f", score.totalScore)) (Reliability Q=\(String(format: "%.0f", score.reliability))%, Capacity R=\(String(format: "%.0f", score.capacity))%)."
    }

    public var recentEvents: [NetworkRoutingEvent] {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryEvents
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        inMemoryEvents.removeAll()
    }
}
