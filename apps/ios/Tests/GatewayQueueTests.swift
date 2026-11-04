import Foundation

public final class GatewayQueueTests {
 public func runAllTests() -> (passed:Int,total:Int) {
  do {
   let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite").path
   defer{try? FileManager.default.removeItem(atPath:path)}
   let db=SQLiteDatabase(customPath:path),q=GatewayQueue(database:db)
   let fixture=try Data(contentsOf:URL(fileURLWithPath:"packages/protocol/fixtures/v1/operation-sos.json"))
   let op=try JSONDecoder().decode(ContractV1.Operation.self,from:fixture)
   let envelope=ContractV1.Envelope(packetId:UUID().uuidString.lowercased(),sourceNodeId:op.originNodeId,destinationNodeId:"*",timestamp:op.timestamp,ttl:4,hopCount:2,type:.syncOp,payload:.syncOp(op))
   try db.captureGatewayEnvelope(envelope);try db.captureGatewayEnvelope(envelope)
   guard try q.counts().pending==1 else {throw GatewayFailure.storage}
   let item=try q.pending()[0]
   guard item.operation==op else {throw GatewayFailure.identityReuse}
   try q.failed(item,permanent:false)
   guard try q.pending().isEmpty else {throw GatewayFailure.storage}
   db.close();db.reopen()
   let restored=try q.pending(now:Date().addingTimeInterval(600))
   guard restored.count==1,restored[0].operation==op,restored[0].attempts==1 else {throw GatewayFailure.storage}
   let peer=ContractV1.Acknowledgment(ackId:UUID().uuidString.lowercased(),operationId:op.operationId,stage:.peerStored,acknowledgingNodeId:op.originNodeId,timestamp:op.timestamp,packetId:envelope.packetId)
   do {try q.committed(item,ack:peer);throw GatewayFailure.storage}catch GatewayFailure.invalidResponse {}
   guard try q.counts().pending==1 else {throw GatewayFailure.storage}
   let ack=ContractV1.Acknowledgment(ackId:UUID().uuidString.lowercased(),operationId:op.operationId,stage:.backendCommitted,acknowledgingNodeId:"00000000-0000-4000-8000-000000000003",timestamp:op.timestamp,entityVersion:1)
   try q.committed(item,ack:ack);db.close();db.reopen()
   guard try q.counts().committed==1,try q.pending(now:Date().addingTimeInterval(600)).isEmpty else {throw GatewayFailure.storage}
   guard GatewayQueue.retryDelay(attempt:0)==2,GatewayQueue.retryDelay(attempt:100)==300 else {throw GatewayFailure.storage}
   let changed=ContractV1.Operation(operationId:op.operationId,originNodeId:op.originNodeId,entityId:op.entityId,timestamp:op.timestamp+1,lamportClock:op.lamportClock,entityType:.sos,action:.create,baseVersion:0,payload:op.payload)
   let changedEnvelope=ContractV1.Envelope(packetId:UUID().uuidString.lowercased(),sourceNodeId:op.originNodeId,destinationNodeId:"*",timestamp:op.timestamp,ttl:4,hopCount:2,type:.syncOp,payload:.syncOp(changed))
   do{try db.captureGatewayEnvelope(changedEnvelope);throw GatewayFailure.storage}catch GatewayFailure.identityReuse{}
   db.close()
   print("[PASS] Gateway persistence: exact identity, duplicate suppression, backoff, reopen, ACK stages, ID reuse")
   return (1,1)
  }catch{print("[FAIL] Gateway persistence: \(error)");return (0,1)}
 }
}
