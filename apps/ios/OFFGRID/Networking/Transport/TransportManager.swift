import Foundation
import UIKit
import Combine

@MainActor
public final class TransportManager: ObservableObject, PeerDiscoveryDelegate {
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

    /// Broadcasts an already-persisted message across available radio transports using Contract v1 rc.2 framing.
    /// Does NOT duplicate the local database insertion.
    @discardableResult
    public func broadcastPersistedMessage(_ message: OFFGRIDMessage, operationId: String) -> Bool {
        let opPayload: ContractV1.OperationPayload
        let entityType: ContractV1.EntityType

        if message.type == .sos {
            entityType = .sos
            let category: ContractV1.SOSCategory
            let contentUpper = message.content.uppercased()
            if contentUpper.contains("MEDICAL") {
                category = .medical
            } else if contentUpper.contains("SUPPLIES") {
                category = .supplies
            } else if contentUpper.contains("OTHER") {
                category = .other
            } else {
                category = .assistance
            }
            opPayload = .sos(ContractV1.SOSPayload(
                text: message.content,
                category: category,
                location: ContractV1.SOSLocation(label: "Off-Grid Beacon", latitude: nil, longitude: nil)
            ))
        } else {
            entityType = .message
            let recipientNodeId: String
            if message.recipientId == "*" || !ContractV1Validator.isValidUUID(message.recipientId) {
                recipientNodeId = ContractV1.broadcastRecipientId
            } else {
                recipientNodeId = message.recipientId.lowercased()
            }
            opPayload = .message(ContractV1.MessagePayload(
                text: message.content,
                recipientNodeId: recipientNodeId
            ))
        }

        let contractOp = ContractV1.Operation(
            schemaVersion: 1,
            operationId: operationId.lowercased(),
            originNodeId: message.senderId.lowercased(),
            entityId: message.id.lowercased(),
            timestamp: Int64(message.timestamp.timeIntervalSince1970 * 1000),
            lamportClock: max(0, message.lamportClock),
            entityType: entityType,
            action: .create,
            baseVersion: 0,
            payload: opPayload
        )

        let envelope = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: localNodeId.lowercased(),
            destinationNodeId: message.recipientId == "*" ? "*" : message.recipientId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(contractOp)
        )

        do {
            try ContractV1Validator.validateEnvelope(envelope)
        } catch {
            logger.log(.error, "Envelope contract validation failed for [\(message.id.prefix(8))]: \(error)")
            messageRepository.updateStatus(id: message.id, status: .failed)
            operationRepository.markStatus(operationId: operationId, status: .failed)
            return false
        }

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
                logger.log(.tx, "Dispatched SYNC_OP envelope [\(envelope.packetId.prefix(8))] for message [\(message.id.prefix(8))] to \(peerCount) peer(s); awaiting ACK")
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
            if (op.entityType == .message || op.entityType == .sos),
               let message = messageRepository.getMessage(id: op.entityId) {
                broadcastPersistedMessage(message, operationId: op.id)
            }
        }
    }

    private func sendPeerStoredAck(for op: ContractV1.Operation, packetId: String, toNodeId: String) {
        let ack = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: op.operationId.lowercased(),
            stage: .peerStored,
            acknowledgingNodeId: self.localNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId.lowercased(),
            entityVersion: nil
        )

        let ackEnvelope = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: self.localNodeId.lowercased(),
            destinationNodeId: toNodeId.lowercased(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(ack)
        )

        do {
            try ContractV1Validator.validateEnvelope(ackEnvelope)
        } catch {
            self.logger.log(.error, "Failed to validate ACK envelope: \(error)")
            return
        }

        guard let ackData = try? JSONEncoder().encode(ackEnvelope) else {
            self.logger.log(.error, "Failed to encode ACK envelope for op [\(op.operationId.prefix(8))]")
            return
        }

        multipeerManager?.broadcast(data: ackData)
        logger.log(.ack, "Dispatched PEER_STORED ACK for op [\(op.operationId.prefix(8))] to [\(toNodeId.prefix(8))]")
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

            // 1. Decode Contract v1 Envelope
            guard let envelope = try? JSONDecoder().decode(ContractV1.Envelope.self, from: data) else {
                self.logger.log(.error, "Malformed packet received from \(peerId) (\(data.count) bytes): not a ContractV1.Envelope")
                return
            }

            // 2. Validate envelope invariants
            do {
                try ContractV1Validator.validateEnvelope(envelope)
            } catch {
                self.logger.log(.error, "Envelope from \(peerId) rejected by Contract v1 validator: \(error)")
                return
            }

            // 3. Prevent self-loopback echoes
            guard envelope.sourceNodeId.caseInsensitiveCompare(self.localNodeId) != .orderedSame else {
                return
            }

            // 4. Route according to envelope type
            switch envelope.type {
            case .syncOp:
                guard case .syncOp(let op) = envelope.payload else {
                    self.logger.log(.error, "Envelope type SYNC_OP has unexpected payload")
                    return
                }

                // Extract content based on payload type
                let text: String
                let recipientId: String
                let msgType: MessageType

                switch op.payload {
                case .message(let msgPayload):
                    text = msgPayload.text
                    recipientId = msgPayload.recipientNodeId
                    msgType = .chat
                case .sos(let sosPayload):
                    text = sosPayload.text
                    recipientId = "*"
                    msgType = .sos
                case .announcement(let annPayload):
                    text = annPayload.text
                    recipientId = "*"
                    msgType = .announcement
                case .tombstone, .none:
                    text = ""
                    recipientId = "*"
                    msgType = .chat
                }

                var receivedMessage = OFFGRIDMessage(
                    id: op.entityId,
                    senderId: op.originNodeId,
                    senderName: op.entityType == .sos ? "SOS-NODE-\(String(op.originNodeId.prefix(4)))" : "Node-\(String(op.originNodeId.prefix(4)))",
                    recipientId: recipientId,
                    content: text,
                    type: msgType,
                    timestamp: Date(timeIntervalSince1970: Double(op.timestamp) / 1000.0),
                    status: .delivered,
                    hopCount: envelope.hopCount + 1,
                    lamportClock: op.lamportClock
                )

                let payloadJsonString: String
                if let p = op.payload, let pData = try? JSONEncoder().encode(p), let str = String(data: pData, encoding: .utf8) {
                    payloadJsonString = str
                } else {
                    payloadJsonString = "{}"
                }

                let offgridOp = OFFGRIDOperation(
                    id: op.operationId,
                    entityType: op.entityType == .sos ? .sos : (op.entityType == .announcement ? .announcement : .message),
                    entityId: op.entityId,
                    action: op.action == .create ? .create : (op.action == .update ? .update : .delete),
                    originNodeId: op.originNodeId,
                    timestamp: Date(timeIntervalSince1970: Double(op.timestamp) / 1000.0),
                    lamportClock: op.lamportClock,
                    payloadJson: payloadJsonString,
                    syncStatus: .peerRelayed
                )

                // Check for existing records prior to enqueueing
                let existingMsg = self.messageRepository.getMessage(id: op.entityId)
                let existingOp = self.operationRepository.getOperation(byOperationId: op.operationId)
                let isDuplicate = (existingMsg != nil || existingOp != nil)

                // Enqueue operation into SQLite with conflict detection
                do {
                    let insertRes = try self.operationRepository.enqueue(operation: offgridOp)
                    self.messageRepository.saveMessage(receivedMessage)
                    if insertRes == .duplicateIdentical {
                        self.logger.log(.rx, "Duplicate operation [\(op.operationId.prefix(8))] received (idempotent no-op)")
                    }
                } catch SQLiteDatabase.OperationStorageError.conflictingPayload(let opId, let existing, let new) {
                    self.logger.log(.error, "Conflicting operation payload for [\(opId.prefix(8))]: existing='\(existing)', new='\(new)'. Dropping without ACK.")
                    return
                } catch {
                    self.logger.log(.error, "Failed to persist inbound operation [\(op.operationId.prefix(8))]: \(error). Dropping without ACK.")
                    return
                }

                // If not duplicate, update UI feeds
                if !isDuplicate {
                    if receivedMessage.type == .sos {
                        self.logger.log(.rx, "EMERGENCY SOS RECEIVED from \(peerId): \"\(receivedMessage.content)\" [\(receivedMessage.id.prefix(8))]")
                        NotificationCenter.default.post(name: TransportManager.didUpdateSOSNotification, object: receivedMessage)
                    } else {
                        self.logger.log(.rx, "Received & saved message [\(receivedMessage.id.prefix(8))] from \(peerId): \"\(receivedMessage.content)\"")
                    }
                    NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)
                }

                // Transmit PEER_STORED ACK only after durable storage succeeds
                self.sendPeerStoredAck(for: op, packetId: envelope.packetId, toNodeId: envelope.sourceNodeId)

            case .ack:
                guard case .ack(let ack) = envelope.payload else {
                    self.logger.log(.error, "Envelope type ACK has unexpected payload")
                    return
                }

                // Validate acknowledgment
                do {
                    try ContractV1Validator.validateAcknowledgment(ack)
                } catch {
                    self.logger.log(.error, "ACK from \(peerId) rejected by Contract v1 validator: \(error)")
                    return
                }

                // Check loopback
                guard ack.acknowledgingNodeId.caseInsensitiveCompare(self.localNodeId) != .orderedSame else {
                    return
                }

                self.logger.log(.ack, "Received \(ack.stage.rawValue) ACK for op [\(ack.operationId.prefix(8))] from \(peerId)")

                // Find corresponding message via operation or directly
                let targetEntityId: String
                if let op = self.operationRepository.getOperation(byOperationId: ack.operationId) {
                    targetEntityId = op.entityId
                } else {
                    targetEntityId = ack.operationId
                }

                // Update status based on ACK stage
                if ack.stage == .backendCommitted {
                    self.operationRepository.markStatus(operationId: ack.operationId, status: .gatewaySynced)
                    self.messageRepository.updateStatus(id: targetEntityId, status: .synced)
                } else {
                    // PEER_STORED or RECIPIENT_ACKNOWLEDGED transitions to peerRelayed / delivered
                    self.operationRepository.markStatus(operationId: ack.operationId, status: .peerRelayed)
                    self.messageRepository.updateStatus(id: targetEntityId, status: .delivered)
                }

                // If acknowledged message was an SOS, broadcast SOS notification
                if let ackedMsg = self.messageRepository.getMessage(id: targetEntityId), ackedMsg.type == .sos {
                    self.logger.log(.ack, "Emergency SOS [\(targetEntityId.prefix(8))] confirmed delivered to peer mesh!")
                    NotificationCenter.default.post(name: TransportManager.didUpdateSOSNotification, object: ackedMsg)
                }

                NotificationCenter.default.post(name: TransportManager.didUpdateMessagesNotification, object: nil)
            }
        }
    }
}
