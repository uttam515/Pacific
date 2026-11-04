import Foundation

public enum GatewayFailure: Error { case storage, identityReuse, invalidConfiguration, invalidResponse, unauthorized, rejected }
public struct GatewayObservation: Codable, Sendable {
    public var schemaVersion = 1
    public let operationId: String
    public let packetId: String
    public let hopCount: Int
    public let receivedAt: Int64
}
public struct GatewayUpload: Sendable {
    public let operation: ContractV1.Operation
    public let observation: String
    public let attempts: Int
}
public final class GatewayQueue: @unchecked Sendable {
    private let db: SQLiteDatabase
    public init(database: SQLiteDatabase = .shared) { self.db=database }
    public func pending(now: Date = Date()) throws -> [GatewayUpload] {
        try db.gatewayRows("SELECT operation_json,observation_json,attempts FROM gateway_upload_queue WHERE state='PENDING' AND next_attempt<=? ORDER BY next_attempt,operation_id LIMIT 20",[String(now.timeIntervalSince1970)]).map { r in
            GatewayUpload(operation:try JSONDecoder().decode(ContractV1.Operation.self,from:Data(r[0].utf8)),observation:r[1],attempts:Int(r[2]) ?? 0)
        }
    }
    public func counts() throws -> (pending:Int,failed:Int,committed:Int) {
        let rows=try db.gatewayRows("SELECT state,count(*) FROM gateway_upload_queue GROUP BY state")
        func count(_ state:String)->Int { Int(rows.first(where:{$0[0]==state})?[1] ?? "0") ?? 0 }
        return (count("PENDING"),count("BLOCKED"),count("COMMITTED"))
    }
    public func committed(_ upload: GatewayUpload, ack: ContractV1.Acknowledgment) throws {
        guard ack.stage == .backendCommitted, ack.operationId == upload.operation.operationId else { throw GatewayFailure.invalidResponse }
        try ContractV1Validator.validateAcknowledgment(ack)
        let encoded=String(data:try JSONEncoder().encode(ack),encoding:.utf8)!
        try db.performTransaction {
            try db.gatewayExecute("UPDATE gateway_upload_queue SET state='COMMITTED',ack_json=?,last_error=NULL WHERE operation_id=?",[encoded,upload.operation.operationId])
            db.updateOperationStatus(id:upload.operation.operationId,status:.gatewaySynced)
            db.updateMessageStatus(id:upload.operation.entityId,status:.synced)
        }
    }
    public static func retryDelay(attempt:Int) -> TimeInterval { min(300,pow(2,Double(min(8,max(0,attempt))))*2) }
    public func failed(_ upload:GatewayUpload,permanent:Bool,now:Date=Date()) throws {
        let next=now.timeIntervalSince1970+Self.retryDelay(attempt:upload.attempts)+Double.random(in:0...1)
        try db.gatewayExecute("UPDATE gateway_upload_queue SET state=?,attempts=attempts+1,next_attempt=?,last_error=? WHERE operation_id=?",[permanent ? "BLOCKED":"PENDING",String(next),permanent ? "REQUIRES_REVIEW":"RETRY_SCHEDULED",upload.operation.operationId])
    }
    public func retryBlocked() throws {
        try db.gatewayExecute("UPDATE gateway_upload_queue SET state='PENDING',next_attempt=0 WHERE state='BLOCKED'")
    }
    public func outstandingObservations() throws -> [(String,String)] {
        try db.gatewayRows("SELECT operation_id,observation_json FROM gateway_upload_queue WHERE state='COMMITTED' AND observation_json IS NOT NULL LIMIT 20").map { ($0[0],$0[1]) }
    }
    public func observed(_ id:String) throws { try db.gatewayExecute("UPDATE gateway_upload_queue SET observation_json=NULL WHERE operation_id=?",[id]) }
}
