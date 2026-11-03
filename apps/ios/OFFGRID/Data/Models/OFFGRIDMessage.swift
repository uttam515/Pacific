import Foundation

public enum MessageDeliveryStatus: String, Codable, Sendable {
    case draft = "DRAFT"
    case pending = "PENDING"
    case relayed = "RELAYED"
    case delivered = "DELIVERED"
    case synced = "SYNCED"
    case failed = "FAILED"
}

public enum MessageType: String, Codable, Sendable {
    case chat = "CHAT"
    case sos = "SOS"
    case announcement = "ANNOUNCEMENT"
}

public struct OFFGRIDMessage: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let senderId: String
    public let senderName: String
    public let recipientId: String // "*" for broadcast
    public let content: String
    public let type: MessageType
    public let timestamp: Date
    public var status: MessageDeliveryStatus
    public var hopCount: Int
    public var lamportClock: Int64

    public init(
        id: String = UUID().uuidString,
        senderId: String,
        senderName: String,
        recipientId: String = "*",
        content: String,
        type: MessageType = .chat,
        timestamp: Date = Date(),
        status: MessageDeliveryStatus = .pending,
        hopCount: Int = 0,
        lamportClock: Int64 = 0
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.recipientId = recipientId
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.status = status
        self.hopCount = hopCount
        self.lamportClock = lamportClock
    }
}
