import Foundation

@MainActor public func runGatewayHTTPAcceptance(configPath:String) async throws {
    let config=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:configPath))) as! [String:String]
    let a=config["nodeA"]!,b=config["nodeB"]!,c=config["nodeC"]!
    let dbA=SQLiteDatabase(inMemory:true),dbB=SQLiteDatabase(inMemory:true)
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"-gateway.sqlite").path
    defer{try? FileManager.default.removeItem(atPath:path)}
    let dbC=SQLiteDatabase(customPath:path)
    let engineA=MeshEngine(localNodeId:a,localDisplayName:"A",database:dbA),engineB=MeshEngine(localNodeId:b,localDisplayName:"B",database:dbB),engineC=MeshEngine(localNodeId:c,localDisplayName:"C",database:dbC)
    typealias Radio=MeshProtocolTests.SimulatedVirtualRadioTransport
    let ra=Radio(nodeId:a,displayName:"A"),rb=Radio(nodeId:b,displayName:"B"),rc=Radio(nodeId:c,displayName:"C")
    ra.link(to:rb);rb.link(to:rc)
    engineA.transportDelegate=ra;engineB.transportDelegate=rb;engineC.transportDelegate=rc
    ra.onPacketDelivered={d,p in engineA.processInboundPacket(data:d,fromPeer:p,transport:.multipeer)}
    rb.onPacketDelivered={d,p in engineB.processInboundPacket(data:d,fromPeer:p,transport:.multipeer)}
    rc.onPacketDelivered={d,p in engineC.processInboundPacket(data:d,fromPeer:p,transport:.multipeer)}
    let entity=UUID().uuidString.lowercased(),opid=UUID().uuidString.lowercased()
    let message=OFFGRIDMessage(id:entity,senderId:a,senderName:"A",recipientId:"*",content:"AUTOMATED TEST MEDICAL: simulated mesh; no real emergency",type:.sos,timestamp:Date(),status:.queued)
    guard engineA.submitOutboundMessage(message,operationId:opid) else {throw GatewayFailure.storage}
    let queue=GatewayQueue(database:dbC)
    guard try queue.counts().pending==1,dbB.getMessage(byId:entity) != nil else {throw GatewayFailure.storage}
    let item=try queue.pending()[0]
    guard item.operation.operationId==opid,item.operation.originNodeId==a else {throw GatewayFailure.identityReuse}
    let manager=GatewayManager(nodeId:c,queue:queue)
    try manager.configure(baseURL:"http://127.0.0.1:1",credential:config["gatewayCredential"]!,allowLocalHTTP:true)
    manager.start();await manager.sync();manager.stop()
    guard try queue.counts().pending==1 else {throw GatewayFailure.storage}
    dbC.close();dbC.reopen()
    try manager.configure(baseURL:config["baseURL"]!,credential:config["gatewayCredential"]!,allowLocalHTTP:true)
    manager.start()
    for _ in 0..<50 {
        if try queue.counts().committed==1 {break}
        await manager.sync();try await Task.sleep(nanoseconds:100_000_000)
    }
    manager.stop()
    guard try queue.counts().committed==1 else {throw GatewayFailure.invalidResponse}
    var req=URLRequest(url:URL(string:config["baseURL"]!+"/api/v1/sync/push")!)
    req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.setValue("Bearer "+config["gatewayCredential"]!,forHTTPHeaderField:"Authorization")
    req.httpBody=try JSONEncoder().encode(ContractV1.PushRequest(nodeId:c,operations:[item.operation]))
    let (data,response)=try await URLSession.shared.data(for:req)
    let push=try JSONDecoder().decode(ContractV1.PushResponse.self,from:data)
    guard (response as? HTTPURLResponse)?.statusCode==200,push.results.first?.duplicate==true,push.results.first?.outcome == .committed else {throw GatewayFailure.invalidResponse}
    var snapshotReq=URLRequest(url:URL(string:config["baseURL"]!+"/api/v1/emergency/snapshot")!)
    snapshotReq.setValue("Bearer "+config["operatorCredential"]!,forHTTPHeaderField:"Authorization")
    let (snapshot,_)=try await URLSession.shared.data(for:snapshotReq)
    let json=try JSONSerialization.jsonObject(with:snapshot) as! [String:Any]
    let incidents=json["incidents"] as! [[String:Any]]
    guard incidents.filter({$0["operation_id"] as? String==opid}).count==1 else {throw GatewayFailure.invalidResponse}
    print("[PASS] Native Swift A→B→C simulated mesh → actual HTTP/PostgreSQL → dashboard snapshot → duplicate=true; unavailable endpoint and SQLite reopen recovery")
    dbA.close();dbB.close();dbC.close()
}
