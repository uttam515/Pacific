import Foundation

public enum ContractValidationError: Error, CustomStringConvertible, Equatable {
    case invalidSchemaVersion(expected: Int, actual: Int)
    case invalidUUID(field: String, value: String)
    case integerOutOfRange(field: String, value: Int64, min: Int64, max: Int64)
    case invalidTTL(ttl: Int, hopCount: Int)
    case invalidBaseVersion(action: String, baseVersion: Int64?)
    case missingEntityVersionForBackendCommitted
    case payloadTypeMismatch(expected: String, reason: String)
    case emptyText(field: String)
    case textExceedsLimit(field: String, length: Int, limit: Int)
    case invalidCoordinates(lat: Double?, lon: Double?)
    case emptyOperationList
    case tooManyOperations(count: Int)
    case unknownSchema(name: String)
    case custom(String)
    
    public var description: String {
        switch self {
        case .invalidSchemaVersion(let exp, let act):
            return "Invalid schemaVersion: expected \(exp), got \(act)"
        case .invalidUUID(let field, let val):
            return "Field '\(field)' is not a valid lowercase UUIDv4: '\(val)'"
        case .integerOutOfRange(let field, let val, let min, let max):
            return "Integer field '\(field)' value \(val) outside range [\(min), \(max)]"
        case .invalidTTL(let ttl, let hopCount):
            return "Invalid TTL/hopCount: ttl=\(ttl), hopCount=\(hopCount). Must satisfy 0 <= ttl <= 8, 0 <= hopCount <= 8, hopCount + ttl <= 8."
        case .invalidBaseVersion(let action, let base):
            return "Invalid baseVersion \(String(describing: base)) for action \(action)"
        case .missingEntityVersionForBackendCommitted:
            return "entityVersion is required and must be >= 1 when stage is BACKEND_COMMITTED"
        case .payloadTypeMismatch(let exp, let reason):
            return "Payload type mismatch for \(exp): \(reason)"
        case .emptyText(let field):
            return "Text field '\(field)' cannot be empty (minLength: 1)"
        case .textExceedsLimit(let field, let len, let limit):
            return "Text field '\(field)' has length \(len), exceeding limit of \(limit)"
        case .invalidCoordinates(let lat, let lon):
            return "Invalid coordinates: lat=\(String(describing: lat)), lon=\(String(describing: lon))"
        case .emptyOperationList:
            return "Operations array cannot be empty (minItems: 1)"
        case .tooManyOperations(let count):
            return "Operations array has \(count) items, exceeding limit of 100"
        case .unknownSchema(let name):
            return "Unknown schema name: \(name)"
        case .custom(let msg):
            return msg
        }
    }
}

public struct ContractV1Validator {
    
    private static let uuidPredicate = NSPredicate(format: "SELF MATCHES %@", ContractV1.uuidRegex)
    private static let cursorPredicate = NSPredicate(format: "SELF MATCHES %@", ContractV1.cursorRegex)
    
    public static func isValidUUID(_ str: String) -> Bool {
        return uuidPredicate.evaluate(with: str)
    }
    
    public static func isValidCursor(_ str: String) -> Bool {
        return cursorPredicate.evaluate(with: str)
    }
    
    public static func validateUUID(_ str: String, field: String) throws {
        if !isValidUUID(str) {
            throw ContractValidationError.invalidUUID(field: field, value: str)
        }
    }
    
    public static func validateInteger(_ val: Int64, field: String, min: Int64 = 0, max: Int64 = ContractV1.maxSafeInteger) throws {
        if val < min || val > max {
            throw ContractValidationError.integerOutOfRange(field: field, value: val, min: min, max: max)
        }
    }
    
    // MARK: - Model Validators
    
    public static func validateOperation(_ op: ContractV1.Operation) throws {
        if op.schemaVersion != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: op.schemaVersion)
        }
        try validateUUID(op.operationId, field: "operationId")
        try validateUUID(op.originNodeId, field: "originNodeId")
        try validateUUID(op.entityId, field: "entityId")
        try validateInteger(op.timestamp, field: "timestamp")
        try validateInteger(op.lamportClock, field: "lamportClock")
        
        switch op.action {
        case .create:
            if op.baseVersion != 0 {
                throw ContractValidationError.invalidBaseVersion(action: op.action.rawValue, baseVersion: op.baseVersion)
            }
        case .update:
            guard let base = op.baseVersion, base >= 1 else {
                throw ContractValidationError.invalidBaseVersion(action: op.action.rawValue, baseVersion: op.baseVersion)
            }
            try validateInteger(base, field: "baseVersion", min: 1)
        case .delete:
            guard let base = op.baseVersion, base >= 1 else {
                throw ContractValidationError.invalidBaseVersion(action: op.action.rawValue, baseVersion: op.baseVersion)
            }
            try validateInteger(base, field: "baseVersion", min: 1)
            if op.payload != nil && op.payload != .none {
                throw ContractValidationError.payloadTypeMismatch(expected: "null", reason: "DELETE operations must have null payload")
            }
        }
        
        switch op.payload {
        case .message(let m):
            if m.text.isEmpty {
                throw ContractValidationError.emptyText(field: "payload.text")
            }
            if m.text.count > 1024 {
                throw ContractValidationError.textExceedsLimit(field: "payload.text", length: m.text.count, limit: 1024)
            }
            try validateUUID(m.recipientNodeId, field: "payload.recipientNodeId")
            
        case .sos(let s):
            if s.text.isEmpty {
                throw ContractValidationError.emptyText(field: "payload.text")
            }
            if s.text.count > 1024 {
                throw ContractValidationError.textExceedsLimit(field: "payload.text", length: s.text.count, limit: 1024)
            }
            if s.location.label.isEmpty {
                throw ContractValidationError.emptyText(field: "payload.location.label")
            }
            if s.location.label.count > 256 {
                throw ContractValidationError.textExceedsLimit(field: "payload.location.label", length: s.location.label.count, limit: 256)
            }
            if let lat = s.location.latitude, let lon = s.location.longitude {
                if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0 {
                    throw ContractValidationError.invalidCoordinates(lat: lat, lon: lon)
                }
            } else if s.location.latitude != nil || s.location.longitude != nil {
                throw ContractValidationError.invalidCoordinates(lat: s.location.latitude, lon: s.location.longitude)
            }
            
        case .announcement(let a):
            if a.text.isEmpty {
                throw ContractValidationError.emptyText(field: "payload.text")
            }
            if a.text.count > 1000 {
                throw ContractValidationError.textExceedsLimit(field: "payload.text", length: a.text.count, limit: 1000)
            }
            
        case .tombstone:
            if op.action != .delete {
                throw ContractValidationError.payloadTypeMismatch(expected: op.entityType.rawValue, reason: "Payload missing for action \(op.action)")
            }
        case .none:
            if op.action != .delete {
                throw ContractValidationError.payloadTypeMismatch(expected: op.entityType.rawValue, reason: "Payload missing for action \(op.action)")
            }
        }
    }
    
    public static func validateAcknowledgment(_ ack: ContractV1.Acknowledgment) throws {
        if ack.schemaVersion != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: ack.schemaVersion)
        }
        try validateUUID(ack.ackId, field: "ackId")
        try validateUUID(ack.operationId, field: "operationId")
        try validateUUID(ack.acknowledgingNodeId, field: "acknowledgingNodeId")
        try validateInteger(ack.timestamp, field: "timestamp")
        
        if let packetId = ack.packetId {
            try validateUUID(packetId, field: "packetId")
        }
        
        if ack.stage == .backendCommitted {
            guard let entityVersion = ack.entityVersion, entityVersion >= 1 else {
                throw ContractValidationError.missingEntityVersionForBackendCommitted
            }
            try validateInteger(entityVersion, field: "entityVersion", min: 1)
        }
    }
    
    public static func validateEnvelope(_ env: ContractV1.Envelope) throws {
        if env.version != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: env.version)
        }
        try validateUUID(env.packetId, field: "packetId")
        try validateUUID(env.sourceNodeId, field: "sourceNodeId")
        if env.destinationNodeId != "*" {
            try validateUUID(env.destinationNodeId, field: "destinationNodeId")
        }
        try validateInteger(env.timestamp, field: "timestamp")
        
        if env.ttl < 0 || env.ttl > 8 || env.hopCount < 0 || env.hopCount > 8 || (env.hopCount + env.ttl) > 8 {
            throw ContractValidationError.invalidTTL(ttl: env.ttl, hopCount: env.hopCount)
        }
        
        switch env.payload {
        case .syncOp(let op):
            try validateOperation(op)
        case .ack(let ack):
            try validateAcknowledgment(ack)
        }
    }
    
    public static func validatePushRequest(_ req: ContractV1.PushRequest) throws {
        if req.schemaVersion != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: req.schemaVersion)
        }
        try validateUUID(req.nodeId, field: "nodeId")
        if req.operations.isEmpty {
            throw ContractValidationError.emptyOperationList
        }
        if req.operations.count > 100 {
            throw ContractValidationError.tooManyOperations(count: req.operations.count)
        }
        for op in req.operations {
            try validateOperation(op)
        }
    }
    
    public static func validatePushResponse(_ res: ContractV1.PushResponse) throws {
        if res.schemaVersion != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: res.schemaVersion)
        }
        try validateUUID(res.requestId, field: "requestId")
        try validateInteger(res.serverLamportClock, field: "serverLamportClock")
    }
    
    public static func validatePullResponse(_ res: ContractV1.PullResponse) throws {
        if res.schemaVersion != ContractV1.schemaVersion {
            throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: res.schemaVersion)
        }
        try validateInteger(res.serverLamportClock, field: "serverLamportClock")
        if let nextCursor = res.nextCursor {
            if !isValidCursor(nextCursor) {
                throw ContractValidationError.custom("Invalid cursor: \(nextCursor)")
            }
        }
    }
    
    // MARK: - Raw JSON Pre-checks & Fixture Validation
    
    public static func validateRawJSON(data: Data, expectedSchema: String) throws {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContractValidationError.custom("Root JSON must be an object")
        }
        
        // Strict pre-check: ensure payload in operations is not a string
        if let payload = jsonObject["payload"], payload is String {
            throw ContractValidationError.payloadTypeMismatch(expected: "Object", reason: "Payload must be a JSON object, not an escaped string")
        }
        
        let decoder = JSONDecoder()
        
        switch expectedSchema {
        case "Operation":
            let op = try decoder.decode(ContractV1.Operation.self, from: data)
            try validateOperation(op)
            
        case "Acknowledgment":
            let ack = try decoder.decode(ContractV1.Acknowledgment.self, from: data)
            try validateAcknowledgment(ack)
            
        case "Envelope":
            // Pre-check negative or invalid TTL/hopCount
            if let ttl = jsonObject["ttl"] as? Int, (ttl < 0 || ttl > 8) {
                let hop = jsonObject["hopCount"] as? Int ?? 0
                throw ContractValidationError.invalidTTL(ttl: ttl, hopCount: hop)
            }
            let env = try decoder.decode(ContractV1.Envelope.self, from: data)
            try validateEnvelope(env)
            
        case "PushRequest":
            if let v = jsonObject["schemaVersion"] as? Int, v != ContractV1.schemaVersion {
                throw ContractValidationError.invalidSchemaVersion(expected: ContractV1.schemaVersion, actual: v)
            }
            let req = try decoder.decode(ContractV1.PushRequest.self, from: data)
            try validatePushRequest(req)
            
        case "PushResponse":
            let res = try decoder.decode(ContractV1.PushResponse.self, from: data)
            try validatePushResponse(res)
            
        case "PullResponse":
            let res = try decoder.decode(ContractV1.PullResponse.self, from: data)
            try validatePullResponse(res)
            
        case "Conflict":
            _ = try decoder.decode(ContractV1.Conflict.self, from: data)
            
        case "ConflictList":
            _ = try decoder.decode(ContractV1.ConflictList.self, from: data)
            
        case "ResolveRequest":
            _ = try decoder.decode(ContractV1.ResolveRequest.self, from: data)
            
        case "ResolveResponse":
            _ = try decoder.decode(ContractV1.ResolveResponse.self, from: data)
            
        case "Notification":
            _ = try decoder.decode(ContractV1.Notification.self, from: data)
            
        case "ReceiptRequest":
            _ = try decoder.decode(ContractV1.ReceiptRequest.self, from: data)
            
        case "ReceiptResponse":
            _ = try decoder.decode(ContractV1.ReceiptResponse.self, from: data)
            
        case "ErrorResponse":
            _ = try decoder.decode(ContractV1.ErrorResponse.self, from: data)
            
        case "Health":
            _ = try decoder.decode(ContractV1.Health.self, from: data)
            
        case "DashboardSnapshot":
            _ = try decoder.decode(ContractV1.DashboardSnapshot.self, from: data)
            
        default:
            throw ContractValidationError.unknownSchema(name: expectedSchema)
        }
    }
}
