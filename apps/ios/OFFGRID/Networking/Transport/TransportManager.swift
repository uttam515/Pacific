import Foundation
import UIKit
import Combine

@MainActor
public final class TransportManager: ObservableObject, PeerDiscoveryDelegate {
    public static let didUpdateMessagesNotification = Notification.Name("OFFGRIDDidUpdateMessagesNotification")

    @Published public var activePeers: [DiscoveredPeer] = []
    @Published public var connectedPeers: [DiscoveredPeer] = []
    @Published public var isGatewayConnected: Bool = false
    @Published public var lastReceivedPacketTime: Date?
    @Published public var isAdvertising: Bool = false
    @Published public var isBrowsing: Bool = false

    public let localNodeId: String
    public let localDeviceName: String

    private var multipeerManager: MultipeerSessionManager?
    private var bleManager: BLEManager?
    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private let logger: NetworkDiagnosticLogger = .shared

    public init(
        nodeDisplayName: String? = nil,
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        let nodeId = KeychainHelper.shared.getOrCreateNodeId()
        self.localNodeId = nodeId
        let devName = UIDevice.current.name
        self.localDeviceName = devName

        let resolvedDisplayName = nodeDisplayName ?? "\(devName)-\(String(nodeId.prefix(4)))"

        let multipeer = MultipeerSessionManager(displayName: resolvedDisplayName)
        self.multipeerManager = multipeer
        self.bleManager = BLEManager()

        multipeer.delegate = self
        self.bleManager?.delegate = self

        multipeer.onDiagnosticLog = { [weak self] category, message in
            self?.logger.log(category, message)
        }
    }

    public func startAllTransports() {
        multipeerManager?.start()
        isAdvertising = multipeerManager?.isAdvertising ?? false
        isBrowsing = multipeerManager?.isBrowsing ?? false
        bleManager?.start()
        logger.log(.system, "All mesh transports activated for node \(String(localNodeId.prefix(8)))")
    }

    public func stopAllTransports() {
        multipeerManager?.stop()
        isAdvertising = false
        isBrowsing = false
        activePeers.removeAll()
        connectedPeers.removeAll()
        bleManager?.stop()
        logger.log(.system, "All mesh transports stopped")
    }

    /// Broadcasts an already-persisted message across available radio transports.
    /// Does NOT duplicate the local database insertion.
    @discardableResult
    public func broadcastPersistedMessage(_ message: OFFGRIDMessage, operationId: String) -> Bool {
        let envelope = WirePacketEnvelope(
            packetId: message.id,
            type: message.type == .sos ? .sos : .message,
            sourceNodeId: message.senderId,
            destinationNodeId: message.recipientId,
            payload: message
        )

        guard let packetData = try? JSONEncoder().encode(envelope) else {
            messageRepository.updateStatus(id: message.id, status: .failed)
            operationRepository.markStatus(operationId: operationId, status: .failed)
            logger.log(.error, "Serialization failed for message [\(message.id.prefix(8))]")
            return false
        }

        var transmitted = false

        // 1. Attempt Multipeer broadcast if peers are connected
        if let multipeer = multipeerManager, multipeer.hasConnectedPeers {
            let result = multipeer.broadcast(data: packetData)
            switch result {
            case .success(let peerCount):
                transmitted = true
                logger.log(.tx, "Dispatched message [\(message.id.prefix(8))] to \(peerCount) peer(s); awaiting ACK")
            case .failure(let error):
                logger.log(.error, "Multipeer broadcast failed: \(error.localizedDescription)")
            }
        }

        // 2. BLE peripheral/central broadcast will hook here when paired

        if transmitted {
            // Relayed over local mesh hop; not yet delivered until peer ACK is received
            messageRepository.updateStatus(id: message.id, status: .relayed)
            operationRepository.markStatus(operationId: operationId, status: .peerRelayed)
            return true
        } else {
            // No connected peers right now: keep locally queued in SQLite without data loss
            messageRepository.updateStatus(id: message.id, status: .queued)
            operationRepository.markStatus(operationId: operationId, status: .queued)
            logger.log(.tx, "No connected peers. Message [\(message.id.prefix(8))] queued locally in SQLite")
            return false
        }
    }

    public func flushPendingQueue() {
        guard let multipeer = multipeerManager, multipeer.hasConnectedPeers else { return }
        let pendingOps = operationRepository.getPendingOperations()

        let eligibleOps = pendingOps.filter { $0.syncStatus == .localOnly || $0.syncStatus == .queued }
        guard !eligibleOps.isEmpty else { return }

        logger.log(.system, "Flushing \(eligibleOps.count) pending operation(s) to connected peers")
        for op in eligibleOps {
            if op.entityType == .message, let message = messageRepository.getMessage(id: op.entityId) {
                broadcastPersistedMessage(message, operationId: op.id)
            }
        }
    }

    private func sendAck(for packetId: String, toNodeId: String) {
        let ackPayload = AckPacketPayload(
            acknowledgedPacketId: packetId,
            receivingNodeId: self.localNodeId
        )
        let ackEnvelope = WirePacketEnvelope(
            packetId: UUID().uuidString,
            type: .ack,
            sourceNodeId: self.localNodeId,
            destinationNodeId: toNodeId,
            payload: ackPayload
        )

        guard let ackData = try? JSONEncoder().encode(ackEnvelope) else { return }
        multipeerManager?.broadcast(data: ackData)
        logger.log(.ack, "Dispatched delivery ACK for packet [\(packetId.prefix(8))] to [\(toNodeId.prefix(8))]")
    }

    // MARK: - PeerDiscoveryDelegate

    public nonisolated func didDiscoverPeer(_ peer: DiscoveredPeer) {
        Task { @MainActor in
            if let index = self.activePeers.firstIndex(where: { $0.id == peer.id }) {
                self.activePeers[index] = peer
            } else {
                self.activePeers.append(peer)
            }

            if peer.isConnected {
                if !self.connectedPeers.contains(where: { $0.id == peer.id }) {
                    self.connectedPeers.append(peer)
                    // Peer newly connected: flush any pending messages from local SQLite queue
                    self.flushPendingQueue()
                }
            } else {
                self.connectedPeers.removeAll { $0.id == peer.id }
            }

            self.isAdvertising = self.multipeerManager?.isAdvertising ?? false
            self.isBrowsing = self.multipeerManager?.isBrowsing ?? false
        }
    }

    public nonisolated func didLosePeer(_ peerId: String) {
        Task { @MainActor in
            self.activePeers.removeAll { $0.id == peerId }
            self.connectedPeers.removeAll { $0.id == peerId }
        }
    }

    public nonisolated func didReceivePacketData(_ data: Data, from peerId: String, transport: TransportType) {
        Task { @MainActor in
            self.lastReceivedPacketTime = Date()

            // 1. Decode generic packet header
            guard let header = try? JSONDecoder().decode(WirePacketHeader.self, from: data) else {
                self.logger.log(.error, "Malformed packet header received from \(peerId) (\(data.count) bytes)")
                return
            }

            // 2. Validate header invariants
            do {
                try PacketValidator.shared.validateHeader(header)
            } catch {
                self.logger.log(.error, "Packet header rejected: \(error)")
                return
            }

            // 3. Prevent self-loopback echoes
            guard header.sourceNodeId != self.localNodeId else {
                return
            }

            // 4. Route according to wire packet type
            switch header.type {
            case .message, .sos:
                guard let envelope = try? JSONDecoder().decode(WirePacketEnvelope<OFFGRIDMessage>.self, from: data) else {
                    self.logger.log(.error, "Failed to decode \(header.type.rawValue) envelope from \(peerId)")
                    return
                }

                let messageId = envelope.payload.id

                // Prevent duplicate message insertion
                if let _ = self.messageRepository.getMessage(id: messageId) {
                    self.logger.log(.rx, "Duplicate message [\(messageId.prefix(8))] received from \(peerId); suppressing insert")
                    // Still return ACK in case previous ACK was lost in transit
                    self.sendAck(for: messageId, toNodeId: header.sourceNodeId)
                    return
                }

                // New message: persist locally with delivered status
                var receivedMessage = envelope.payload
                receivedMessage.status = .delivered
                self.messageRepository.saveMessage(receivedMessage)

                // Enqueue operation in SQLite
                if let json = try? JSONEncoder().encode(receivedMessage),
                   let jsonString = String(data: json, encoding: .utf8) {
                    let op = OFFGRIDOperation(
                        entityType: .message,
                        entityId: receivedMessage.id,
                        action: .create,
                        originNodeId: receivedMessage.senderId,
                        lamportClock: receivedMessage.lamportClock,
                        payloadJson: jsonString,
                        syncStatus: .peerRelayed
                    )
                    self.operationRepository.enqueue(operation: op)
                }

                self.logger.log(.rx, "Received & saved message [\(messageId.prefix(8))] from \(peerId): \"\(receivedMessage.content)\"")
                NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)

                // Transmit ACK back to sender
                self.sendAck(for: messageId, toNodeId: header.sourceNodeId)

            case .ack:
                guard let envelope = try? JSONDecoder().decode(WirePacketEnvelope<AckPacketPayload>.self, from: data) else {
                    self.logger.log(.error, "Failed to decode ACK envelope from \(peerId)")
                    return
                }

                let ack = envelope.payload
                self.logger.log(.ack, "Received delivery ACK for message [\(ack.acknowledgedPacketId.prefix(8))] from \(peerId)")

                // Only receiving a verified ACK transitions message status to DELIVERED
                self.messageRepository.updateStatus(id: ack.acknowledgedPacketId, status: .delivered)
                self.operationRepository.markStatus(operationId: ack.acknowledgedPacketId, status: .peerRelayed)

                NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)

            case .announcement, .syncOp, .heartbeat:
                self.logger.log(.system, "Received \(header.type.rawValue) packet from \(peerId)")
            }
        }
    }
}
