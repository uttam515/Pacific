import Foundation

public enum WirePacketType: String, Codable, Sendable {
    case sos = "SOS"
    case message = "MESSAGE"
    case ack = "ACK"
    case announcement = "ANNOUNCEMENT"
    case syncOp = "SYNC_OP"
    case heartbeat = "HEARTBEAT"
}

public struct WirePacketHeader: Codable, Sendable {
    public let version: Int
    public let packetId: String
    public let type: WirePacketType
    public let sourceNodeId: String
    public let destinationNodeId: String
    public let timestamp: Int64
    public var ttl: Int
    public var hopCount: Int

    public init(
        version: Int = 1,
        packetId: String = UUID().uuidString,
        type: WirePacketType,
        sourceNodeId: String,
        destinationNodeId: String = "*",
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        ttl: Int = 5,
        hopCount: Int = 0
    ) {
        self.version = version
        self.packetId = packetId
        self.type = type
        self.sourceNodeId = sourceNodeId
        self.destinationNodeId = destinationNodeId
        self.timestamp = timestamp
        self.ttl = ttl
        self.hopCount = hopCount
    }
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

    public var header: WirePacketHeader {
        WirePacketHeader(
            version: version,
            packetId: packetId,
            type: type,
            sourceNodeId: sourceNodeId,
            destinationNodeId: destinationNodeId,
            timestamp: timestamp,
            ttl: ttl,
            hopCount: hopCount
        )
    }
}

public struct AckPacketPayload: Codable, Sendable, Equatable {
    public let acknowledgedPacketId: String
    public let receivingNodeId: String
    public let timestamp: Int64

    public init(
        acknowledgedPacketId: String,
        receivingNodeId: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.acknowledgedPacketId = acknowledgedPacketId
        self.receivingNodeId = receivingNodeId
        self.timestamp = timestamp
    }
}

public enum PacketValidationError: Error, CustomStringConvertible {
    case invalidVersion(Int)
    case missingPacketId
    case missingSourceNodeId
    case zeroOrNegativeTTL
    case futureTimestamp(Int64)
    case unparseableHeader(String)
    case unparseablePayload(String)

    public var description: String {
        switch self {
        case .invalidVersion(let v): return "Invalid protocol version: \(v)"
        case .missingPacketId: return "Missing packet identifier"
        case .missingSourceNodeId: return "Missing source node identifier"
        case .zeroOrNegativeTTL: return "Packet TTL is zero or negative"
        case .futureTimestamp(let ts): return "Packet timestamp is in future: \(ts)"
        case .unparseableHeader(let msg): return "Unparseable packet header: \(msg)"
        case .unparseablePayload(let msg): return "Unparseable packet payload: \(msg)"
        }
    }
}

public final class PacketValidator: Sendable {
    public static let shared = PacketValidator()

    public func validateHeader(_ header: WirePacketHeader) throws {
        guard header.version > 0 else {
            throw PacketValidationError.invalidVersion(header.version)
        }
        guard !header.packetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PacketValidationError.missingPacketId
        }
        guard !header.sourceNodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PacketValidationError.missingSourceNodeId
        }
        guard header.ttl > 0 else {
            throw PacketValidationError.zeroOrNegativeTTL
        }
    }
}
