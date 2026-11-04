import Foundation

/// Legacy adapter retained for source compatibility. Active SOS uploads are owned
/// by TransportManager.gatewayManager and its canonical SQLite queue.
public final class SyncEngine: @unchecked Sendable {
    public init(operationRepository: OperationQueueRepository = OperationQueueRepository(), messageRepository: MessageRepository = MessageRepository(), session: URLSession = .shared, gatewayURLString: String? = nil) {}
    @available(*, deprecated, message: "Configure the node-bound GatewayManager in Sync settings")
    public func setGatewayURL(_ urlString: String) {}
    public func syncPendingOperations() async {}
}
