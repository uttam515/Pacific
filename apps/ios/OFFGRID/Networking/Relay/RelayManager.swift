import Foundation

public final class RelayManager: Sendable {
    public static let shared = RelayManager()

    private let maxHopLimit = 5

    public func shouldRelayPacket(currentHopCount: Int, ttl: Int, destinationNodeId: String, myNodeId: String) -> Bool {
        // Do not relay if packet was meant for me
        if destinationNodeId == myNodeId {
            return false
        }
        // Do not relay if hop limit reached or TTL expired
        if currentHopCount >= maxHopLimit || ttl <= 1 {
            return false
        }
        return true
    }

    public func prepareRelayEnvelope<T: Codable & Sendable>(envelope: inout WirePacketEnvelope<T>) {
        envelope.hopCount += 1
        envelope.ttl -= 1
    }
}
