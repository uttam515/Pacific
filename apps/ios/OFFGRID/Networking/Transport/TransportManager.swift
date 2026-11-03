import Foundation

@MainActor
public final class TransportManager: ObservableObject, PeerDiscoveryDelegate {
    @Published public var activePeers: [DiscoveredPeer] = []
    @Published public var isGatewayConnected: Bool = false
    @Published public var lastReceivedPacketTime: Date?

    private var multipeerManager: MultipeerSessionManager?
    private var bleManager: BLEManager?
    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository

    public init(
        nodeDisplayName: String = "iPhone-\(UIDevice.current.name)",
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository

        self.multipeerManager = MultipeerSessionManager(displayName: nodeDisplayName)
        self.bleManager = BLEManager()

        self.multipeerManager?.delegate = self
        self.bleManager?.delegate = self
    }

    public func startAllTransports() {
        multipeerManager?.start()
        bleManager?.start()
    }

    public func stopAllTransports() {
        multipeerManager?.stop()
        bleManager?.stop()
    }

    public func broadcastMessage(_ message: OFFGRIDMessage) {
        // 1. Save locally to SQLite first (offline-first requirement)
        messageRepository.saveMessage(message)

        // 2. Wrap into operation record
        if let json = try? JSONEncoder().encode(message), let jsonString = String(data: json, encoding: .utf8) {
            let op = OFFGRIDOperation(
                entityType: .message,
                entityId: message.id,
                action: .create,
                originNodeId: message.senderId,
                lamportClock: message.lamportClock,
                payloadJson: jsonString,
                syncStatus: .localOnly
            )
            operationRepository.enqueue(operation: op)
        }

        // 3. Encode into wire packet envelope
        let envelope = WirePacketEnvelope(
            type: message.type == .sos ? .sos : .message,
            sourceNodeId: message.senderId,
            destinationNodeId: message.recipientId,
            payload: message
        )

        guard let packetData = try? JSONEncoder().encode(envelope) else { return }

        // 4. Transmit via Multipeer
        multipeerManager?.broadcast(data: packetData)
    }

    // MARK: - PeerDiscoveryDelegate

    public nonisolated func didDiscoverPeer(_ peer: DiscoveredPeer) {
        Task { @MainActor in
            if let index = self.activePeers.firstIndex(where: { $0.id == peer.id }) {
                self.activePeers[index] = peer
            } else {
                self.activePeers.append(peer)
            }
        }
    }

    public nonisolated func didLosePeer(_ peerId: String) {
        Task { @MainActor in
            self.activePeers.removeAll { $0.id == peerId }
        }
    }

    public nonisolated func didReceivePacketData(_ data: Data, from peerId: String, transport: TransportType) {
        Task { @MainActor in
            self.lastReceivedPacketTime = Date()
            if let envelope = try? JSONDecoder().decode(WirePacketEnvelope<OFFGRIDMessage>.self, from: data) {
                var message = envelope.payload
                message.status = .delivered
                self.messageRepository.saveMessage(message)
            }
        }
    }
}

import UIKit
