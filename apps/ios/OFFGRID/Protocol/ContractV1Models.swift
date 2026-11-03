import Foundation

/// Canonical Contract v1 Types for OFFGRID (revision 1.0.0-rc.2)
/// Adheres strictly to packages/protocol/schemas/v1/contract.schema.json
public enum ContractV1 {
    
    // MARK: - Constants & Regex
    
    public static let schemaVersion: Int = 1
    public static let maxSafeInteger: Int64 = 9_007_199_254_740_991
    public static let uuidRegex = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    public static let cursorRegex = "^c[0-9]{1,20}$"
    public static let broadcastRecipientId = "00000000-0000-4000-8000-000000000000"
    
    // MARK: - Enums
    
    public enum EntityType: String, Codable, Sendable, CaseIterable {
        case message = "MESSAGE"
        case sos = "SOS"
        case announcement = "ANNOUNCEMENT"
    }
    
    public enum Action: String, Codable, Sendable, CaseIterable {
        case create = "CREATE"
        case update = "UPDATE"
        case delete = "DELETE"
    }
    
    public enum AckStage: String, Codable, Sendable, CaseIterable {
        case peerStored = "PEER_STORED"
        case backendCommitted = "BACKEND_COMMITTED"
        case recipientAcknowledged = "RECIPIENT_ACKNOWLEDGED"
    }
    
    public enum SOSCategory: String, Codable, Sendable, CaseIterable {
        case assistance = "ASSISTANCE"
        case medical = "MEDICAL"
        case supplies = "SUPPLIES"
        case other = "OTHER"
    }
    
    public enum EnvelopeType: String, Codable, Sendable, CaseIterable {
        case syncOp = "SYNC_OP"
        case ack = "ACK"
    }
    
    public enum PushOutcome: String, Codable, Sendable, CaseIterable {
        case committed = "COMMITTED"
        case conflict = "CONFLICT"
        case rejected = "REJECTED"
    }
    
    public enum ChangeKind: String, Codable, Sendable, CaseIterable {
        case committedOperation = "COMMITTED_OPERATION"
        case conflictChanged = "CONFLICT_CHANGED"
        case acknowledgment = "ACKNOWLEDGMENT"
    }
    
    // MARK: - Payloads
    
    public struct MessagePayload: Codable, Sendable, Equatable {
        public let text: String
        public let recipientNodeId: String
        
        public init(text: String, recipientNodeId: String) {
            self.text = text
            self.recipientNodeId = recipientNodeId
        }
    }
    
    public struct SOSLocation: Codable, Sendable, Equatable {
        public let label: String
        public let latitude: Double?
        public let longitude: Double?
        
        public init(label: String, latitude: Double? = nil, longitude: Double? = nil) {
            self.label = label
            self.latitude = latitude
            self.longitude = longitude
        }
    }
    
    public struct SOSPayload: Codable, Sendable, Equatable {
        public let text: String
        public let category: SOSCategory
        public let location: SOSLocation
        
        public init(text: String, category: SOSCategory, location: SOSLocation) {
            self.text = text
            self.category = category
            self.location = location
        }
    }
    
    public struct AnnouncementPayload: Codable, Sendable, Equatable {
        public let text: String
        
        public init(text: String) {
            self.text = text
        }
    }
    
    public enum OperationPayload: Codable, Sendable, Equatable {
        case message(MessagePayload)
        case sos(SOSPayload)
        case announcement(AnnouncementPayload)
        case tombstone

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let msg = try? container.decode(MessagePayload.self) {
                self = .message(msg)
            } else if let sos = try? container.decode(SOSPayload.self) {
                self = .sos(sos)
            } else if let ann = try? container.decode(AnnouncementPayload.self) {
                self = .announcement(ann)
            } else if container.decodeNil() {
                self = .tombstone
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown operation payload format"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .message(let msg):
                try container.encode(msg)
            case .sos(let sos):
                try container.encode(sos)
            case .announcement(let ann):
                try container.encode(ann)
            case .tombstone:
                try container.encodeNil()
            }
        }
    }
    
    // MARK: - Core Protocol Models
    
    public struct Operation: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let operationId: String
        public let originNodeId: String
        public let entityId: String
        public let timestamp: Int64
        public let lamportClock: Int64
        public let entityType: EntityType
        public let action: Action
        public let baseVersion: Int64?
        public let payload: OperationPayload?
        
        enum CodingKeys: String, CodingKey {
            case schemaVersion
            case operationId
            case originNodeId
            case entityId
            case timestamp
            case lamportClock
            case entityType
            case action
            case baseVersion
            case payload
        }
        
        public init(
            schemaVersion: Int = 1,
            operationId: String,
            originNodeId: String,
            entityId: String,
            timestamp: Int64,
            lamportClock: Int64,
            entityType: EntityType,
            action: Action,
            baseVersion: Int64? = 0,
            payload: OperationPayload?
        ) {
            self.schemaVersion = schemaVersion
            self.operationId = operationId
            self.originNodeId = originNodeId
            self.entityId = entityId
            self.timestamp = timestamp
            self.lamportClock = lamportClock
            self.entityType = entityType
            self.action = action
            self.baseVersion = baseVersion
            self.payload = payload
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            self.operationId = try container.decode(String.self, forKey: .operationId)
            self.originNodeId = try container.decode(String.self, forKey: .originNodeId)
            self.entityId = try container.decode(String.self, forKey: .entityId)
            self.timestamp = try container.decode(Int64.self, forKey: .timestamp)
            self.lamportClock = try container.decode(Int64.self, forKey: .lamportClock)
            self.entityType = try container.decode(EntityType.self, forKey: .entityType)
            self.action = try container.decode(Action.self, forKey: .action)
            self.baseVersion = try container.decodeIfPresent(Int64.self, forKey: .baseVersion)
            
            if action == .delete {
                self.payload = .tombstone
            } else {
                switch entityType {
                case .message:
                    let p = try container.decode(MessagePayload.self, forKey: .payload)
                    self.payload = .message(p)
                case .sos:
                    let p = try container.decode(SOSPayload.self, forKey: .payload)
                    self.payload = .sos(p)
                case .announcement:
                    let p = try container.decode(AnnouncementPayload.self, forKey: .payload)
                    self.payload = .announcement(p)
                }
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(operationId, forKey: .operationId)
            try container.encode(originNodeId, forKey: .originNodeId)
            try container.encode(entityId, forKey: .entityId)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(lamportClock, forKey: .lamportClock)
            try container.encode(entityType, forKey: .entityType)
            try container.encode(action, forKey: .action)
            
            if let baseVersion = baseVersion {
                try container.encode(baseVersion, forKey: .baseVersion)
            }
            
            switch payload {
            case .message(let p):
                try container.encode(p, forKey: .payload)
            case .sos(let p):
                try container.encode(p, forKey: .payload)
            case .announcement(let p):
                try container.encode(p, forKey: .payload)
            case .tombstone, .none:
                if action == .delete {
                    try container.encodeNil(forKey: .payload)
                }
            }
        }
    }
    
    public struct Acknowledgment: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let ackId: String
        public let operationId: String
        public let stage: AckStage
        public let acknowledgingNodeId: String
        public let timestamp: Int64
        public let packetId: String?
        public let entityVersion: Int64?
        
        enum CodingKeys: String, CodingKey {
            case schemaVersion
            case ackId
            case operationId
            case stage
            case acknowledgingNodeId
            case timestamp
            case packetId
            case entityVersion
        }
        
        public init(
            schemaVersion: Int = 1,
            ackId: String,
            operationId: String,
            stage: AckStage,
            acknowledgingNodeId: String,
            timestamp: Int64,
            packetId: String? = nil,
            entityVersion: Int64? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.ackId = ackId
            self.operationId = operationId
            self.stage = stage
            self.acknowledgingNodeId = acknowledgingNodeId
            self.timestamp = timestamp
            self.packetId = packetId
            self.entityVersion = entityVersion
        }
    }
    
    // MARK: - Envelopes
    
    public enum EnvelopePayload: Sendable, Equatable {
        case syncOp(Operation)
        case ack(Acknowledgment)
    }
    
    public struct Envelope: Codable, Sendable, Equatable {
        public let version: Int
        public let packetId: String
        public let sourceNodeId: String
        public let destinationNodeId: String
        public let timestamp: Int64
        public let ttl: Int
        public let hopCount: Int
        public let type: EnvelopeType
        public let payload: EnvelopePayload
        
        enum CodingKeys: String, CodingKey {
            case version
            case packetId
            case sourceNodeId
            case destinationNodeId
            case timestamp
            case ttl
            case hopCount
            case type
            case payload
        }
        
        public init(
            version: Int = 1,
            packetId: String,
            sourceNodeId: String,
            destinationNodeId: String,
            timestamp: Int64,
            ttl: Int,
            hopCount: Int,
            type: EnvelopeType,
            payload: EnvelopePayload
        ) {
            self.version = version
            self.packetId = packetId
            self.sourceNodeId = sourceNodeId
            self.destinationNodeId = destinationNodeId
            self.timestamp = timestamp
            self.ttl = ttl
            self.hopCount = hopCount
            self.type = type
            self.payload = payload
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(Int.self, forKey: .version)
            self.packetId = try container.decode(String.self, forKey: .packetId)
            self.sourceNodeId = try container.decode(String.self, forKey: .sourceNodeId)
            self.destinationNodeId = try container.decode(String.self, forKey: .destinationNodeId)
            self.timestamp = try container.decode(Int64.self, forKey: .timestamp)
            self.ttl = try container.decode(Int.self, forKey: .ttl)
            self.hopCount = try container.decode(Int.self, forKey: .hopCount)
            self.type = try container.decode(EnvelopeType.self, forKey: .type)
            
            switch self.type {
            case .syncOp:
                let op = try container.decode(Operation.self, forKey: .payload)
                self.payload = .syncOp(op)
            case .ack:
                let ack = try container.decode(Acknowledgment.self, forKey: .payload)
                self.payload = .ack(ack)
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(packetId, forKey: .packetId)
            try container.encode(sourceNodeId, forKey: .sourceNodeId)
            try container.encode(destinationNodeId, forKey: .destinationNodeId)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(ttl, forKey: .ttl)
            try container.encode(hopCount, forKey: .hopCount)
            try container.encode(type, forKey: .type)
            
            switch payload {
            case .syncOp(let op):
                try container.encode(op, forKey: .payload)
            case .ack(let ack):
                try container.encode(ack, forKey: .payload)
            }
        }
    }
    
    // MARK: - REST Gateway Synchronization Models
    
    public struct ContractError: Codable, Sendable, Equatable {
        public let code: String
        public let message: String
        public let details: [String: AnyCodable]?
        
        public init(code: String, message: String, details: [String: AnyCodable]? = nil) {
            self.code = code
            self.message = message
            self.details = details
        }
    }
    
    public struct ErrorResponse: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let error: ContractError
        
        public init(schemaVersion: Int = 1, error: ContractError) {
            self.schemaVersion = schemaVersion
            self.error = error
        }
    }
    
    public struct PushRequest: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let nodeId: String
        public let operations: [Operation]
        
        public init(schemaVersion: Int = 1, nodeId: String, operations: [Operation]) {
            self.schemaVersion = schemaVersion
            self.nodeId = nodeId
            self.operations = operations
        }
    }
    
    public struct PushResult: Codable, Sendable, Equatable {
        public let operationId: String
        public let outcome: PushOutcome
        public let duplicate: Bool?
        public let entityVersion: Int64?
        public let ack: Acknowledgment?
        public let conflictId: String?
        public let error: ContractError?
        
        public init(
            operationId: String,
            outcome: PushOutcome,
            duplicate: Bool? = nil,
            entityVersion: Int64? = nil,
            ack: Acknowledgment? = nil,
            conflictId: String? = nil,
            error: ContractError? = nil
        ) {
            self.operationId = operationId
            self.outcome = outcome
            self.duplicate = duplicate
            self.entityVersion = entityVersion
            self.ack = ack
            self.conflictId = conflictId
            self.error = error
        }
    }
    
    public struct PushResponse: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let requestId: String
        public let results: [PushResult]
        public let serverLamportClock: Int64
        
        public init(schemaVersion: Int = 1, requestId: String, results: [PushResult], serverLamportClock: Int64) {
            self.schemaVersion = schemaVersion
            self.requestId = requestId
            self.results = results
            self.serverLamportClock = serverLamportClock
        }
    }
    
    public struct Change: Codable, Sendable, Equatable {
        public let sequence: String
        public let kind: ChangeKind
        public let operation: Operation?
        public let entityVersion: Int64?
        public let committedAt: Int64?
        public let conflictId: String?
        public let revision: Int?
        public let timestamp: Int64?
        public let ack: Acknowledgment?
        
        public init(
            sequence: String,
            kind: ChangeKind,
            operation: Operation? = nil,
            entityVersion: Int64? = nil,
            committedAt: Int64? = nil,
            conflictId: String? = nil,
            revision: Int? = nil,
            timestamp: Int64? = nil,
            ack: Acknowledgment? = nil
        ) {
            self.sequence = sequence
            self.kind = kind
            self.operation = operation
            self.entityVersion = entityVersion
            self.committedAt = committedAt
            self.conflictId = conflictId
            self.revision = revision
            self.timestamp = timestamp
            self.ack = ack
        }
    }
    
    public struct PullResponse: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let changes: [Change]
        public let nextCursor: String?
        public let hasMore: Bool
        public let serverLamportClock: Int64
        
        public init(
            schemaVersion: Int = 1,
            changes: [Change],
            nextCursor: String? = nil,
            hasMore: Bool,
            serverLamportClock: Int64
        ) {
            self.schemaVersion = schemaVersion
            self.changes = changes
            self.nextCursor = nextCursor
            self.hasMore = hasMore
            self.serverLamportClock = serverLamportClock
        }
    }
    
    // MARK: - Additional Schema Types for Fixtures
    
    public struct ConflictCandidate: Codable, Sendable, Equatable {
        public let operation: Operation
        
        public init(operation: Operation) {
            self.operation = operation
        }
    }
    
    public struct Conflict: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let conflictId: String
        public let entityId: String
        public let baseVersion: Int64
        public let revision: Int
        public let currentEntityVersion: Int
        public let status: String
        public let candidates: [ConflictCandidate]
        public let resolutionOperationId: String?
        public let selectedOperationId: String?
        
        public init(
            schemaVersion: Int = 1,
            conflictId: String,
            entityId: String,
            baseVersion: Int64,
            revision: Int,
            currentEntityVersion: Int,
            status: String,
            candidates: [ConflictCandidate],
            resolutionOperationId: String? = nil,
            selectedOperationId: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.conflictId = conflictId
            self.entityId = entityId
            self.baseVersion = baseVersion
            self.revision = revision
            self.currentEntityVersion = currentEntityVersion
            self.status = status
            self.candidates = candidates
            self.resolutionOperationId = resolutionOperationId
            self.selectedOperationId = selectedOperationId
        }
    }
    
    public struct ConflictList: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let conflicts: [Conflict]
        public let nextCursor: String?
        public let hasMore: Bool?
        
        public init(schemaVersion: Int = 1, conflicts: [Conflict], nextCursor: String? = nil, hasMore: Bool? = nil) {
            self.schemaVersion = schemaVersion
            self.conflicts = conflicts
            self.nextCursor = nextCursor
            self.hasMore = hasMore
        }
    }
    
    public struct ResolveRequest: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let operationId: String
        public let resolverNodeId: String
        public let selectedOperationId: String
        public let expectedConflictRevision: Int
        public let expectedEntityVersion: Int
        public let timestamp: Int64
        public let lamportClock: Int64
        
        public init(
            schemaVersion: Int = 1,
            operationId: String,
            resolverNodeId: String,
            selectedOperationId: String,
            expectedConflictRevision: Int,
            expectedEntityVersion: Int,
            timestamp: Int64,
            lamportClock: Int64
        ) {
            self.schemaVersion = schemaVersion
            self.operationId = operationId
            self.resolverNodeId = resolverNodeId
            self.selectedOperationId = selectedOperationId
            self.expectedConflictRevision = expectedConflictRevision
            self.expectedEntityVersion = expectedEntityVersion
            self.timestamp = timestamp
            self.lamportClock = lamportClock
        }
    }
    
    public struct ResolveResponse: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let resolutionOperationId: String
        public let duplicate: Bool
        public let conflict: Conflict
        public let ack: Acknowledgment
        
        public init(
            schemaVersion: Int = 1,
            resolutionOperationId: String,
            duplicate: Bool,
            conflict: Conflict,
            ack: Acknowledgment
        ) {
            self.schemaVersion = schemaVersion
            self.resolutionOperationId = resolutionOperationId
            self.duplicate = duplicate
            self.conflict = conflict
            self.ack = ack
        }
    }
    
    public struct Notification: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let type: String
        public let eventId: String
        public let timestamp: Int64
        public let latestCursor: String
        
        public init(schemaVersion: Int = 1, type: String, eventId: String, timestamp: Int64, latestCursor: String) {
            self.schemaVersion = schemaVersion
            self.type = type
            self.eventId = eventId
            self.timestamp = timestamp
            self.latestCursor = latestCursor
        }
    }
    
    public struct ReceiptRequest: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let nodeId: String
        public let ack: Acknowledgment
        
        public init(schemaVersion: Int = 1, nodeId: String, ack: Acknowledgment) {
            self.schemaVersion = schemaVersion
            self.nodeId = nodeId
            self.ack = ack
        }
    }
    
    public struct ReceiptResponse: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let acceptedAckId: String
        public let duplicate: Bool
        
        public init(schemaVersion: Int = 1, acceptedAckId: String, duplicate: Bool) {
            self.schemaVersion = schemaVersion
            self.acceptedAckId = acceptedAckId
            self.duplicate = duplicate
        }
    }
    
    public struct Health: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let status: String
    }
    
    public struct DashboardSnapshot: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let observedAt: Int64
        public let nodes: [AnyCodable]
        public let links: [AnyCodable]
        public let operations: [AnyCodable]
        public let alerts: [AnyCodable]
        public let conflicts: [AnyCodable]
        public let gateways: [AnyCodable]
        public let events: [AnyCodable]
    }
}

// MARK: - AnyCodable Utility

public struct AnyCodable: Codable, @unchecked Sendable, Equatable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int64.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AnyCodable value")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported AnyCodable value"))
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case (let l as Bool, let r as Bool):
            return l == r
        case (let l as Int64, let r as Int64):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as String, let r as String):
            return l == r
        case (let l as [AnyCodable], let r as [AnyCodable]):
            return l == r
        default:
            return false
        }
    }
}
