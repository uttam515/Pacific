import Foundation

public enum WirePacketType: String, Codable, Sendable {
    case sos = "SOS"
    case message = "MESSAGE"
    case ack = "ACK"
    case announcement = "ANNOUNCEMENT"
    case syncOp = "SYNC_OP"
    case heartbeat = "HEARTBEAT"
}

public struct WirePacketEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let packetId: String
    public let type: WirePacketType
    public let sourceNodeId: String
    public let destinationNodeId: String
    public let timestamp: Int64
    public var ttl: Int
    public var hopCount: Int
    public let payload: T
    public var signature: String?

    public init(
        version: Int = 1,
        packetId: String = UUID().uuidString,
        type: WirePacketType,
        sourceNodeId: String,
        destinationNodeId: String = "*",
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        ttl: Int = 5,
        hopCount: Int = 0,
        payload: T,
        signature: String? = nil
    ) {
        self.version = version
        self.packetId = packetId
        self.type = type
        self.sourceNodeId = sourceNodeId
        self.destinationNodeId = destinationNodeId
        self.timestamp = timestamp
        self.ttl = ttl
        self.hopCount = hopCount
        self.payload = payload
        self.signature = signature
    }
}

public struct AckPacketPayload: Codable, Sendable {
    public let acknowledgedPacketId: String
    public let receivingNodeId: String
    public let timestamp: Int64

    public init(acknowledgedPacketId: String, receivingNodeId: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.acknowledgedPacketId = acknowledgedPacketId
        self.receivingNodeId = receivingNodeId
        self.timestamp = timestamp
    }
}
