import Foundation
import Network
import Combine

public struct GatewayConfiguration: Codable {
    public let nodeId: String
    public let baseURL: URL
    public let bearerCredential: String
    public let allowLocalHTTP: Bool
    public func validate(existingNodeId:String) throws {
        guard nodeId==existingNodeId,ContractV1Validator.isValidUUID(nodeId),
              bearerCredential.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil,
              baseURL.user==nil,baseURL.password==nil,baseURL.query==nil,baseURL.fragment==nil,
              baseURL.path.isEmpty || baseURL.path=="/",let host=baseURL.host else { throw GatewayFailure.invalidConfiguration }
        if baseURL.scheme=="https" { return }
        let parts=host.split(separator:".").compactMap{Int($0)}
        let privateIPv4=parts.count==4 && parts.allSatisfy{(0...255).contains($0)} && (parts[0]==10 || (parts[0]==192 && parts[1]==168) || (parts[0]==172 && (16...31).contains(parts[1])))
        guard allowLocalHTTP,baseURL.scheme=="http",privateIPv4 || host=="localhost" || host=="127.0.0.1" || host.hasSuffix(".local") else { throw GatewayFailure.invalidConfiguration }
    }
}
// NWPath is a trigger only. Authenticated readiness checks database access.
@MainActor public final class GatewayManager: ObservableObject {
    @Published public private(set) var status="Gateway not configured"
    @Published public private(set) var pendingCount=0
    @Published public private(set) var failedCount=0
    @Published public private(set) var committedCount=0
    @Published public private(set) var backendReachable=false
    private let queue:GatewayQueue
    private let nodeId:String
    private var configuration:GatewayConfiguration?
    private let monitor=NWPathMonitor()
    private var loop:Task<Void,Never>?
    private var running=false
    private var active=false
    private var meshConnected=false
    private let session:URLSession
    public init(nodeId:String,queue:GatewayQueue=GatewayQueue(),session:URLSession = URLSession(configuration:.ephemeral,delegate:GatewayNoRedirect(),delegateQueue:nil)) {
        self.nodeId=nodeId;self.queue=queue;self.session=session
        if let data=KeychainHelper.shared.read(key:"gateway-config-v1"),let c=try? JSONDecoder().decode(GatewayConfiguration.self,from:data),(try? c.validate(existingNodeId:nodeId)) != nil {
            configuration=c;status="Ready to check backend"
        }
        monitor.pathUpdateHandler={ [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in await self?.sync() } }
        }
        monitor.start(queue:DispatchQueue(label:"org.offgrid.gateway.path"))
        refreshCounts()
    }
    public func configure(baseURL:String,credential:String,allowLocalHTTP:Bool) throws {
        guard let url=URL(string:baseURL) else { throw GatewayFailure.invalidConfiguration }
        let c=GatewayConfiguration(nodeId:nodeId,baseURL:url,bearerCredential:credential,allowLocalHTTP:allowLocalHTTP)
        try c.validate(existingNodeId:nodeId)
        guard KeychainHelper.shared.saveDeviceOnly(key:"gateway-config-v1",data:try JSONEncoder().encode(c)) else { throw GatewayFailure.storage }
        configuration=c;status="Credential saved; checking backend"
    }
    public func setMeshConnected(_ value:Bool) { meshConnected=value }
    public func start() {
        active=true;guard loop==nil else { return }
        loop=Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(nanoseconds:15_000_000_000)
            }
        }
    }
    public func stop() { active=false;loop?.cancel();loop=nil;backendReachable=false;status="Paused while app is inactive; queue retained" }
    public func retryBlocked() { do {try queue.retryBlocked();status="Retry enabled"}catch{status="Queue storage failure"} }
    private func refreshCounts() {
        do {let c=try queue.counts();pendingCount=c.pending;failedCount=c.failed;committedCount=c.committed}
        catch {status="Queue storage failure; uploads paused"}
    }
    private func request(_ path:String,body:Data?=nil) async throws -> (Data,Int) {
        guard let c=configuration else { throw GatewayFailure.invalidConfiguration }
        var req=URLRequest(url:c.baseURL.appendingPathComponent(path));req.timeoutInterval=15
        req.httpMethod=body==nil ? "GET":"POST";req.httpBody=body
        req.setValue("Bearer "+c.bearerCredential,forHTTPHeaderField:"Authorization")
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response)=try await session.data(for:req)
        guard let r=response as? HTTPURLResponse,r.url?.host==c.baseURL.host,r.url?.scheme==c.baseURL.scheme else {throw GatewayFailure.invalidResponse}
        return (data,r.statusCode)
    }
    public func sync() async {
        guard active,!running,configuration != nil else {refreshCounts();return}
        running=true;defer{running=false;refreshCounts()}
        do {
            let (readyData,code)=try await request("api/v1/gateway/ready")
            guard code==200,let ready=try JSONSerialization.jsonObject(with:readyData) as? [String:Any],ready["ready"] as? Bool==true,ready["nodeId"] as? String==nodeId,let serverId=ready["serverNodeId"] as? String else {throw GatewayFailure.unauthorized}
            backendReachable=true;status="Backend reachable; uploading queued SOS"
            for item in try queue.pending() {
                if Task.isCancelled || !active {return}
                do {
                    let body=try JSONEncoder().encode(ContractV1.PushRequest(nodeId:nodeId,operations:[item.operation]))
                    let (data,http)=try await request("api/v1/sync/push",body:body)
                    guard http==200 else {
                        try queue.failed(item,permanent:[400,403,413,422].contains(http))
                        if http==401||http==403 {throw GatewayFailure.unauthorized};continue
                    }
                    let response=try JSONDecoder().decode(ContractV1.PushResponse.self,from:data)
                    guard response.schemaVersion==1,response.results.count==1,let result=response.results.first,result.operationId==item.operation.operationId else {throw GatewayFailure.invalidResponse}
                    if result.outcome == .committed {
                        guard result.duplicate != nil,let ack=result.ack,ack.acknowledgingNodeId==serverId,result.entityVersion==ack.entityVersion else {throw GatewayFailure.invalidResponse}
                        try queue.committed(item,ack:ack)
                    }else{
                        let root=try JSONSerialization.jsonObject(with:data) as? [String:Any]
                        let results=root?["results"] as? [[String:Any]]
                        let retry=(results?.first?["error"] as? [String:Any])?["retryable"] as? Bool ?? false
                        try queue.failed(item,permanent:!retry)
                    }
                }catch GatewayFailure.unauthorized {throw GatewayFailure.unauthorized}
                catch {try queue.failed(item,permanent:false);backendReachable=false;status="Upload interrupted; durable retry scheduled";break}
            }
            for (id,json) in try queue.outstandingObservations() {
                let (_,code)=try await request("api/v1/gateway/observations",body:Data(json.utf8))
                if code==200 {try queue.observed(id)}
            }
            let c=try queue.counts()
            let heartbeat:[String:Any]=["schemaVersion":1,"nodeId":nodeId,"reportedAt":Int64(Date().timeIntervalSince1970*1000),"meshConnected":meshConnected,"internetReachable":backendReachable,"pendingUploads":c.pending,"failedUploads":c.failed]
            let (_,heartbeatCode)=try await request("api/v1/gateway/heartbeat",body:try JSONSerialization.data(withJSONObject:heartbeat))
            guard heartbeatCode==200 else {throw GatewayFailure.invalidResponse}
            status=c.failed>0 ? "Some SOS uploads need review; retained locally":"Backend synchronized; gateway available while app is active"
        }catch GatewayFailure.unauthorized {backendReachable=false;status="Gateway authorization required; existing identity and queue retained"}
        catch {backendReachable=false;status="Backend unreachable; queued SOS retained for retry"}
    }
}

public final class GatewayNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse, newRequest request:URLRequest, completionHandler:@escaping (URLRequest?)->Void) { completionHandler(nil) }
}
