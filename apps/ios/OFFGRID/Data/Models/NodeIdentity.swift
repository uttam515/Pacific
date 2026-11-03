import Foundation

public enum HardwarePlatform: String, Codable, Sendable {
    case iOS = "IOS"
    case android = "ANDROID"
    case server = "SERVER"
    case web = "WEB"
}

public struct NodeIdentity: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var displayName: String
    public let hardwarePlatform: HardwarePlatform
    public var isGateway: Bool
    public var lastSeen: Date
    public var batteryLevel: Float?

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        hardwarePlatform: HardwarePlatform = .iOS,
        isGateway: Bool = false,
        lastSeen: Date = Date(),
        batteryLevel: Float? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hardwarePlatform = hardwarePlatform
        self.isGateway = isGateway
        self.lastSeen = lastSeen
        self.batteryLevel = batteryLevel
    }
}
