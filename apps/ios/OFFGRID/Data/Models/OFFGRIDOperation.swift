import Foundation

public enum OperationAction: String, Codable, Sendable {
    case create = "CREATE"
    case update = "UPDATE"
    case delete = "DELETE"
}

public enum OperationEntity: String, Codable, Sendable {
    case message = "MESSAGE"
    case sos = "SOS"
    case announcement = "ANNOUNCEMENT"
}

public enum SyncStatus: String, Codable, Sendable {
    case localOnly = "LOCAL_ONLY"
    case peerRelayed = "PEER_RELAYED"
    case gatewaySynced = "GATEWAY_SYNCED"
    case conflict = "CONFLICT"
}

public struct OFFGRIDOperation: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let entityType: OperationEntity
    public let entityId: String
    public let action: OperationAction
    public let originNodeId: String
    public let timestamp: Date
    public var lamportClock: Int64
    public let payloadJson: String
    public var syncStatus: SyncStatus
    public var retryCount: Int

    public init(
        id: String = UUID().uuidString,
        entityType: OperationEntity,
        entityId: String,
        action: OperationAction,
        originNodeId: String,
        timestamp: Date = Date(),
        lamportClock: Int64 = 0,
        payloadJson: String,
        syncStatus: SyncStatus = .localOnly,
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.originNodeId = originNodeId
        self.timestamp = timestamp
        self.lamportClock = lamportClock
        self.payloadJson = payloadJson
        self.syncStatus = syncStatus
        self.retryCount = retryCount
    }
}
