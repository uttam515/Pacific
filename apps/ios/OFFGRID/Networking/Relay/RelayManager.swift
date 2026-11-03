import Foundation

public enum RelayError: Error, LocalizedError {
    case hopLimitExceeded(current: Int, max: Int)
    case ttlExpired(ttl: Int)
    case localDestinationReached(nodeId: String)
    case noEligiblePeers
    case invalidPacket(String)

    public var errorDescription: String? {
        switch self {
        case .hopLimitExceeded(let current, let max):
            return "Packet exceeded maximum hop limit: \(current) >= \(max)"
        case .ttlExpired(let ttl):
            return "Packet TTL expired: ttl=\(ttl)"
        case .localDestinationReached(let nodeId):
            return "Packet destination reached local node [\(nodeId)]; no relay needed"
        case .noEligiblePeers:
            return "No eligible connected peers available for forwarding"
        case .invalidPacket(let msg):
            return "Invalid relay packet: \(msg)"
        }
    }
}

public final class RelayManager: Sendable {
    public static let shared = RelayManager()

    public let maxHopLimit: Int

    public init(maxHopLimit: Int = 5) {
        self.maxHopLimit = min(8, maxHopLimit)
    }

    /// Evaluates whether an incoming envelope should be relayed across the mesh
    public func shouldRelay(
        envelope: ContractV1.Envelope,
        localNodeId: String,
        incomingFromPeer: String
    ) -> Bool {
        // 1. If packet destination is solely local node, destination reached -> do NOT relay
        if envelope.destinationNodeId != "*" &&
            envelope.destinationNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame {
            return false
        }

        // 2. Prevent self-echo relay loops if packet originated from local node
        if envelope.sourceNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame {
            return false
        }

        // 3. Enforce hop limit and TTL bounds
        if envelope.hopCount >= maxHopLimit || envelope.ttl <= 1 {
            return false
        }

        // 4. Contract v1 rc.2 invariant: hopCount + ttl <= 8
        if (envelope.hopCount + envelope.ttl) > 8 {
            return false
        }

        return true
    }

    /// Validates packet formatting and hop boundaries according to Contract v1 rc.2
    public func validatePacket(envelope: ContractV1.Envelope) throws {
        try ContractV1Validator.validateEnvelope(envelope)

        if envelope.hopCount >= maxHopLimit {
            throw RelayError.hopLimitExceeded(current: envelope.hopCount, max: maxHopLimit)
        }

        if envelope.ttl <= 1 {
            throw RelayError.ttlExpired(ttl: envelope.ttl)
        }
    }

    /// Prepares a new envelope for relaying:
    /// - Increments hopCount by 1
    /// - Decrements ttl by 1
    /// - Preserves original sourceNodeId, destinationNodeId, timestamp, and Operation payload
    public func prepareRelayEnvelope(envelope: ContractV1.Envelope) -> ContractV1.Envelope {
        return ContractV1.Envelope(
            version: envelope.version,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: envelope.sourceNodeId.lowercased(),
            destinationNodeId: envelope.destinationNodeId.lowercased(),
            timestamp: envelope.timestamp,
            ttl: max(0, envelope.ttl - 1),
            hopCount: envelope.hopCount + 1,
            type: envelope.type,
            payload: envelope.payload
        )
    }
}
