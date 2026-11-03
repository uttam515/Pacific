import Foundation

public enum MeshAckStage: String, Codable, Sendable {
    case received = "RECEIVED"
    case stored = "STORED"
    case delivered = "DELIVERED"
    case failed = "FAILED"
}

public struct ReverseRouteInfo: Sendable {
    public let previousHopPeer: String
    public let originNodeId: String
    public let timestamp: Date

    public init(previousHopPeer: String, originNodeId: String, timestamp: Date = Date()) {
        self.previousHopPeer = previousHopPeer
        self.originNodeId = originNodeId
        self.timestamp = timestamp
    }
}

/// Coordinates multi-hop acknowledgements across distinct delivery stages:
/// 1. RECEIVED
/// 2. STORED (PEER_STORED)
/// 3. DELIVERED (RECIPIENT_ACKNOWLEDGED)
/// 4. FAILED
/// And traverses the reverse path back to original message originator.
public final class AcknowledgementManager: @unchecked Sendable {
    public static let shared = AcknowledgementManager()

    private let database: SQLiteDatabase
    private let lock = NSRecursiveLock()
    private var inMemoryReverseRoutes: [String: ReverseRouteInfo] = [:]

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
    }

    /// Records the reverse path of an inbound packet so ACKs know which peer to travel back to
    public func recordReversePath(
        operationId: String,
        packetId: String,
        incomingFromPeer: String,
        originNodeId: String
    ) {
        lock.lock()
        defer { lock.unlock() }

        let opKey = operationId.lowercased()
        let info = ReverseRouteInfo(previousHopPeer: incomingFromPeer, originNodeId: originNodeId.lowercased())
        inMemoryReverseRoutes[opKey] = info

        database.recordReverseRoute(
            operationId: opKey,
            packetId: packetId.lowercased(),
            previousHopPeer: incomingFromPeer,
            originNodeId: originNodeId.lowercased()
        )
    }

    /// Retrieves the reverse path for an operation
    public func getReverseRoute(operationId: String) -> ReverseRouteInfo? {
        lock.lock()
        defer { lock.unlock() }

        let opKey = operationId.lowercased()
        if let memory = inMemoryReverseRoutes[opKey] {
            return memory
        }

        if let dbRoute = database.getReverseRoute(operationId: opKey) {
            let info = ReverseRouteInfo(previousHopPeer: dbRoute.previousHopPeer, originNodeId: dbRoute.originNodeId)
            inMemoryReverseRoutes[opKey] = info
            return info
        }

        return nil
    }

    /// Creates a Contract v1 PEER_STORED acknowledgment envelope
    public func createPeerStoredAck(
        for op: ContractV1.Operation,
        packetId: String,
        localNodeId: String,
        destinationNodeId: String
    ) -> ContractV1.Envelope {
        let ack = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: op.operationId.lowercased(),
            stage: .peerStored,
            acknowledgingNodeId: localNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId.lowercased(),
            entityVersion: nil
        )

        return ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: localNodeId.lowercased(),
            destinationNodeId: destinationNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(ack)
        )
    }

    /// Creates a Contract v1 RECIPIENT_ACKNOWLEDGED acknowledgment envelope
    public func createRecipientAck(
        for op: ContractV1.Operation,
        packetId: String,
        localNodeId: String,
        destinationNodeId: String
    ) -> ContractV1.Envelope {
        let ack = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: op.operationId.lowercased(),
            stage: .recipientAcknowledged,
            acknowledgingNodeId: localNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId.lowercased(),
            entityVersion: nil
        )

        return ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: localNodeId.lowercased(),
            destinationNodeId: destinationNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(ack)
        )
    }

    /// Prepares an ACK envelope to be forwarded along the reverse path
    public func prepareForwardedAck(envelope: ContractV1.Envelope) -> ContractV1.Envelope {
        return ContractV1.Envelope(
            version: envelope.version,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: envelope.sourceNodeId,
            destinationNodeId: envelope.destinationNodeId,
            timestamp: envelope.timestamp,
            ttl: max(0, envelope.ttl - 1),
            hopCount: envelope.hopCount + 1,
            type: .ack,
            payload: envelope.payload
        )
    }

    /// Determines if an incoming ACK should be forwarded towards its destination
    public func shouldForwardAck(envelope: ContractV1.Envelope, localNodeId: String) -> Bool {
        guard envelope.type == .ack else { return false }
        // If the ACK is meant for the local node, destination reached -> no forward
        if envelope.destinationNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame {
            return false
        }
        // Check hop limit and TTL
        if envelope.hopCount >= 8 || envelope.ttl <= 1 {
            return false
        }
        return true
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        inMemoryReverseRoutes.removeAll()
    }
}
