import Foundation
import UIKit
import Combine

@MainActor
public final class TransportManager: ObservableObject, PeerDiscoveryDelegate, MeshTransportDelegate {
    public static let didUpdateMessagesNotification = Notification.Name("OFFGRIDDidUpdateMessagesNotification")
    public static let didUpdateSOSNotification = Notification.Name("OFFGRIDDidUpdateSOSNotification")

    @Published public var activePeers: [DiscoveredPeer] = []
    @Published public var connectedPeers: [DiscoveredPeer] = []
    @Published public var isGatewayConnected: Bool = false
    @Published public var lastReceivedPacketTime: Date?
    @Published public var isAdvertising: Bool = false
    @Published public var isBrowsing: Bool = false

    public let localNodeId: String
    public let localDeviceName: String
    public let meshEngine: MeshEngine
    public let gatewayManager: GatewayManager

    private nonisolated let multipeerManager: MultipeerSessionManager
    private var bleManager: BLEManager?
    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private let logger: NetworkDiagnosticLogger = .shared
    private var cancellables = Set<AnyCancellable>()

    public init(
        nodeDisplayName: String? = nil,
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        let nodeId = KeychainHelper.shared.getOrCreateNodeId()
        self.localNodeId = nodeId
        self.gatewayManager = GatewayManager(nodeId:nodeId)
        let devName = UIDevice.current.name
        self.localDeviceName = devName

        let resolvedDisplayName = nodeDisplayName ?? "\(devName)-\(String(nodeId.prefix(4)))"

        let multipeer = MultipeerSessionManager(displayName: resolvedDisplayName)
        self.multipeerManager = multipeer
        self.bleManager = BLEManager()

        let engine = MeshEngine(
            localNodeId: nodeId,
            localDisplayName: resolvedDisplayName,
            messageRepository: messageRepository,
            operationRepository: operationRepository
        )
        self.meshEngine = engine

        multipeer.delegate = self
        self.bleManager?.delegate = self
        engine.transportDelegate = self

        multipeer.onDiagnosticLog = { [weak self] category, message in
            self?.logger.log(category, message)
        }

        engine.onDiagnosticLog = { [weak self] category, message in
            self?.logger.log(category, message)
        }

        engine.onMessageReceived = { _ in
            NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)
        }

        engine.onSOSReceived = { receivedMessage in
            NotificationCenter.default.post(name: TransportManager.didUpdateSOSNotification, object: receivedMessage)
            NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)
        }

        engine.onAckReceived = { _ in
            NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)
        }

        gatewayManager.$backendReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                self?.isGatewayConnected = reachable
            }
            .store(in: &cancellables)
    }

    public func startAllTransports() {
        gatewayManager.start()
        multipeerManager.start()
        isAdvertising = multipeerManager.isAdvertising
        isBrowsing = multipeerManager.isBrowsing
        bleManager?.start()
        logger.log(.system, "All mesh transports activated for node \(String(localNodeId.prefix(8)))")
    }

    public func stopAllTransports() {
        gatewayManager.stop()
        multipeerManager.stop()
        isAdvertising = false
        isBrowsing = false
        activePeers.removeAll()
        connectedPeers.removeAll()
        bleManager?.stop()
        logger.log(.system, "All mesh transports stopped")
    }

    /// Broadcasts an already-persisted message across available mesh transports using Contract v1 rc.2 framing.
    @discardableResult
    public func broadcastPersistedMessage(_ message: OFFGRIDMessage, operationId: String) -> Bool {
        return meshEngine.submitOutboundMessage(message, operationId: operationId)
    }

    public func flushPendingQueue() {
        meshEngine.flushPendingQueue()
    }

    // MARK: - MeshTransportDelegate

    public nonisolated func transmitPacketData(_ data: Data, toPeers: [String]?) -> Result<Int, Error> {
        return self.multipeerManager.send(data: data, toPeers: toPeers)
    }

    public nonisolated func getConnectedPeers() -> [DiscoveredPeer] {
        return self.multipeerManager.getConnectedPeerObjects()
    }

    // MARK: - PeerDiscoveryDelegate

    public nonisolated func didDiscoverPeer(_ peer: DiscoveredPeer) {
        Task { @MainActor in
            let wasConnected = self.connectedPeers.contains(where: { $0.id == peer.id })

            if let index = self.activePeers.firstIndex(where: { $0.id == peer.id }) {
                self.activePeers[index] = peer
            } else {
                self.activePeers.append(peer)
            }

            if peer.isConnected {
                if !wasConnected {
                    self.connectedPeers.append(peer)
                    self.meshEngine.handlePeerConnected(peer: peer)
                    self.gatewayManager.setMeshConnected(true)
                }
            } else {
                if wasConnected {
                    self.connectedPeers.removeAll { $0.id == peer.id }
                    self.meshEngine.handlePeerDisconnected(peerId: peer.id)
                    self.gatewayManager.setMeshConnected(!self.connectedPeers.isEmpty)
                }
            }

            self.isAdvertising = self.multipeerManager.isAdvertising
            self.isBrowsing = self.multipeerManager.isBrowsing
        }
    }

    public nonisolated func didLosePeer(_ peerId: String) {
        Task { @MainActor in
            self.activePeers.removeAll { $0.id == peerId }
            self.connectedPeers.removeAll { $0.id == peerId }
            self.meshEngine.handlePeerDisconnected(peerId: peerId)
        }
    }

    public nonisolated func didReceivePacketData(_ data: Data, from peerId: String, transport: TransportType) {
        Task { @MainActor in
            self.lastReceivedPacketTime = Date()
            self.meshEngine.processInboundPacket(data: data, fromPeer: peerId, transport: transport)
        }
    }
}
