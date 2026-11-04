import Foundation

public protocol MeshTransportDelegate: AnyObject, Sendable {
    func transmitPacketData(_ data: Data, toPeers: [String]?) -> Result<Int, Error>
    func getConnectedPeers() -> [DiscoveredPeer]
}

/// Central coordinator for multi-hop packet processing, emergency prioritization,
/// adaptive routing, and reverse-path acknowledgement forwarding.
public final class MeshEngine: @unchecked Sendable {
    public let localNodeId: String
    public let localDisplayName: String

    public let deduplicationManager: DeduplicationManager
    public let relayManager: RelayManager
    public let routingEngine: RoutingEngine
    public let acknowledgementManager: AcknowledgementManager
    public let messageQueue: MessageQueue
    public let networkAnalyzer: NetworkAnalyzer
    public let peerTrustManager: PeerTrustManager

    private let database: SQLiteDatabase
    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    public weak var transportDelegate: MeshTransportDelegate?

    public var onMessageReceived: ((OFFGRIDMessage) -> Void)?
    public var onSOSReceived: ((OFFGRIDMessage) -> Void)?
    public var onAckReceived: ((ContractV1.Acknowledgment) -> Void)?
    public var onDiagnosticLog: ((DiagnosticCategory, String) -> Void)?

    public init(
        localNodeId: String,
        localDisplayName: String,
        database: SQLiteDatabase = .shared,
        messageRepository: MessageRepository? = nil,
        operationRepository: OperationQueueRepository? = nil,
        deduplicationManager: DeduplicationManager? = nil,
        relayManager: RelayManager? = nil,
        routingEngine: RoutingEngine? = nil,
        acknowledgementManager: AcknowledgementManager? = nil,
        messageQueue: MessageQueue? = nil,
        networkAnalyzer: NetworkAnalyzer? = nil,
        peerTrustManager: PeerTrustManager? = nil
    ) {
        self.database = database
        self.localNodeId = localNodeId.lowercased()
        self.localDisplayName = localDisplayName

        let msgRepo = messageRepository ?? MessageRepository(database: database)
        let opRepo = operationRepository ?? OperationQueueRepository(database: database)

        self.messageRepository = msgRepo
        self.operationRepository = opRepo
        self.deduplicationManager = deduplicationManager ?? DeduplicationManager(database: database)
        self.relayManager = relayManager ?? RelayManager()
        self.routingEngine = routingEngine ?? RoutingEngine()
        self.acknowledgementManager = acknowledgementManager ?? AcknowledgementManager(database: database)
        self.messageQueue = messageQueue ?? MessageQueue(messageRepository: msgRepo, operationRepository: opRepo)
        self.networkAnalyzer = networkAnalyzer ?? NetworkAnalyzer(database: database)
        self.peerTrustManager = peerTrustManager ?? PeerTrustManager()

        // Hook backlog provider into routing engine
        self.routingEngine.setBacklogProvider { [weak self] in
            return self?.messageQueue.pendingCount ?? 0
        }
    }

    // MARK: - Outbound Transmission

    /// Submits a message to the mesh engine for prioritization, routing, and dispatch
    @discardableResult
    public func submitOutboundMessage(_ message: OFFGRIDMessage, operationId: String) -> Bool {
        let opPayload: ContractV1.OperationPayload
        let entityType: ContractV1.EntityType
        let priority: MessagePriority

        if message.type == .sos {
            entityType = .sos
            priority = .p0EmergencySOS
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
            priority = .p2NormalMessage
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
            originNodeId: localNodeId,
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
            sourceNodeId: localNodeId,
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
            onDiagnosticLog?(.error, "Validation failed for outbound envelope: \(error)")
            messageRepository.updateStatus(id: message.id, status: .failed)
            operationRepository.markStatus(operationId: operationId, status: .failed)
            return false
        }

        let offgridOp = OFFGRIDOperation(
            id: operationId.lowercased(),
            entityType: entityType == .sos ? .sos : .message,
            entityId: message.id.lowercased(),
            action: .create,
            originNodeId: localNodeId,
            timestamp: message.timestamp,
            lamportClock: message.lamportClock,
            payloadJson: (try? String(data: JSONEncoder().encode(opPayload), encoding: .utf8)) ?? "{}",
            syncStatus: .queued
        )

        do { try database.captureGatewayEnvelope(envelope) }
        catch {
            onDiagnosticLog?(.error, "Canonical gateway persistence failed; no transmission attempted")
            return false
        }
        // Enqueue in priority queue
        messageQueue.enqueue(operation: offgridOp, message: message, priority: priority)

        // Attempt immediate dispatch if peers connected
        return dispatchEnvelope(envelope, messageId: message.id, operationId: operationId)
    }

    // MARK: - Inbound Packet Processing

    /// Processes an incoming packet received from a radio transport
    public func processInboundPacket(data: Data, fromPeer: String, transport: TransportType) {
        // 1. Decode Contract v1 Envelope
        guard let envelope = try? JSONDecoder().decode(ContractV1.Envelope.self, from: data) else {
            onDiagnosticLog?(.error, "Malformed packet from \(fromPeer) (\(data.count) bytes)")
            return
        }

        // 2. Validate envelope format
        do {
            try ContractV1Validator.validateEnvelope(envelope)
        } catch {
            onDiagnosticLog?(.error, "Envelope from \(fromPeer) rejected: \(error)")
            return
        }

        // 3. Prevent self-loopback echoes
        guard envelope.sourceNodeId.caseInsensitiveCompare(localNodeId) != .orderedSame else {
            return
        }

        // 4. Rate-limiting & security checks
        guard peerTrustManager.isPeerTrusted(nodeId: envelope.sourceNodeId) else {
            onDiagnosticLog?(.error, "Rejected packet from untrusted peer [\(envelope.sourceNodeId.prefix(8))]")
            return
        }
        guard !peerTrustManager.isRateLimited(nodeId: fromPeer) else {
            onDiagnosticLog?(.error, "Rate limit exceeded for peer [\(fromPeer)]; packet dropped")
            return
        }

        // 5. Handle envelope types
        switch envelope.type {
        case .syncOp:
            processInboundSyncOp(envelope: envelope, fromPeer: fromPeer)
        case .ack:
            processInboundAck(envelope: envelope, fromPeer: fromPeer)
        }
    }

    private func processInboundSyncOp(envelope: ContractV1.Envelope, fromPeer: String) {
        guard case .syncOp(let op) = envelope.payload else { return }

        // Sanitize sensitive location if not an authorized SOS
        let sanitizedOp = peerTrustManager.sanitizeLocationIfNeeded(op: op)

        // Check deduplication
        let isDup = deduplicationManager.isDuplicate(
            packetId: envelope.packetId,
            operationId: sanitizedOp.operationId,
            entityId: sanitizedOp.entityId
        )

        if isDup {
            onDiagnosticLog?(.rx, "Duplicate operation [\(sanitizedOp.operationId.prefix(8))] received from \(fromPeer) (suppressed)")
            networkAnalyzer.recordEvent(
                type: .loopPrevented,
                messageId: sanitizedOp.entityId,
                sourceNode: fromPeer,
                targetNode: localNodeId,
                explanation: "Suppressed duplicate packet [\(envelope.packetId.prefix(8))] for op [\(sanitizedOp.operationId.prefix(8))]"
            )

            do { try database.captureGatewayEnvelope(envelope) }
            catch { onDiagnosticLog?(.error, "Duplicate gateway identity or storage failure; no ACK"); return }
            // Idempotent ACK to prevent sender retransmitting indefinitely
            sendAppropriateAck(for: sanitizedOp, packetId: envelope.packetId, toPeer: fromPeer, envelope: envelope)
            return
        }

        // Extract message fields
        let text: String
        let recipientId: String
        let msgType: MessageType

        switch sanitizedOp.payload {
        case .message(let p):
            text = p.text
            recipientId = p.recipientNodeId
            msgType = .chat
        case .sos(let p):
            text = p.text
            recipientId = "*"
            msgType = .sos
        case .announcement(let p):
            text = p.text
            recipientId = "*"
            msgType = .announcement
        case .tombstone, .none:
            text = ""
            recipientId = "*"
            msgType = .chat
        }

        let isDestination = (envelope.destinationNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame) || (recipientId == localNodeId)

        let receivedMessage = OFFGRIDMessage(
            id: sanitizedOp.entityId,
            senderId: sanitizedOp.originNodeId,
            senderName: sanitizedOp.entityType == .sos ? "SOS-\(String(sanitizedOp.originNodeId.prefix(4)))" : "Node-\(String(sanitizedOp.originNodeId.prefix(4)))",
            recipientId: recipientId,
            content: text,
            type: msgType,
            timestamp: Date(timeIntervalSince1970: Double(sanitizedOp.timestamp) / 1000.0),
            status: isDestination ? .delivered : .relayed,
            hopCount: envelope.hopCount + 1,
            lamportClock: sanitizedOp.lamportClock
        )

        let payloadJsonString: String
        if let p = sanitizedOp.payload, let pData = try? JSONEncoder().encode(p), let str = String(data: pData, encoding: .utf8) {
            payloadJsonString = str
        } else {
            payloadJsonString = "{}"
        }

        let offgridOp = OFFGRIDOperation(
            id: sanitizedOp.operationId,
            entityType: sanitizedOp.entityType == .sos ? .sos : .message,
            entityId: sanitizedOp.entityId,
            action: sanitizedOp.action == .create ? .create : (sanitizedOp.action == .update ? .update : .delete),
            originNodeId: sanitizedOp.originNodeId,
            timestamp: Date(timeIntervalSince1970: Double(sanitizedOp.timestamp) / 1000.0),
            lamportClock: sanitizedOp.lamportClock,
            payloadJson: payloadJsonString,
            syncStatus: .peerRelayed
        )

        // Atomically persist message & operation
        do {
            try database.saveMessageWithOperation(message: receivedMessage, operation: offgridOp, gatewayEnvelope: envelope)
            deduplicationManager.markProcessed(
                packetId: envelope.packetId,
                operationId: sanitizedOp.operationId,
                entityId: sanitizedOp.entityId,
                originNodeId: sanitizedOp.originNodeId
            )
        } catch {
            onDiagnosticLog?(.error, "Persistence failed for [\(sanitizedOp.operationId.prefix(8))]: \(error); aborting without ACK")
            return
        }

        // Record reverse path for reverse-path ACK traversal
        acknowledgementManager.recordReversePath(
            operationId: sanitizedOp.operationId,
            packetId: envelope.packetId,
            incomingFromPeer: fromPeer,
            originNodeId: sanitizedOp.originNodeId
        )

        // Update UI feeds
        if receivedMessage.type == .sos {
            onDiagnosticLog?(.rx, "EMERGENCY SOS RECEIVED from \(fromPeer) via hop \(envelope.hopCount + 1): \"\(receivedMessage.content)\"")
            onSOSReceived?(receivedMessage)
        } else {
            onDiagnosticLog?(.rx, "Received & persisted message [\(receivedMessage.id.prefix(8))] from \(fromPeer)")
            onMessageReceived?(receivedMessage)
        }

        // Transmit immediate ACK back to sender
        sendAppropriateAck(for: sanitizedOp, packetId: envelope.packetId, toPeer: fromPeer, envelope: envelope)

        // Evaluate and perform multi-hop forwarding if eligible
        if relayManager.shouldRelay(envelope: envelope, localNodeId: localNodeId, incomingFromPeer: fromPeer) {
            forwardRelayPacket(envelope: envelope, incomingFromPeer: fromPeer, op: sanitizedOp)
        }
    }

    private func processInboundAck(envelope: ContractV1.Envelope, fromPeer: String) {
        guard case .ack(let ack) = envelope.payload else { return }

        do {
            try ContractV1Validator.validateAcknowledgment(ack)
        } catch {
            onDiagnosticLog?(.error, "ACK rejected by validator: \(error)")
            return
        }

        guard ack.acknowledgingNodeId.caseInsensitiveCompare(localNodeId) != .orderedSame else {
            return
        }

        onDiagnosticLog?(.ack, "Received \(ack.stage.rawValue) ACK for op [\(ack.operationId.prefix(8))] from \(fromPeer)")

        let isDestinationForAck = (envelope.destinationNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame)

        // Update local database status
        let targetEntityId: String
        if let storedOp = operationRepository.getOperation(byOperationId: ack.operationId) {
            targetEntityId = storedOp.entityId
        } else {
            targetEntityId = ack.operationId
        }

        let alreadyCommitted = operationRepository.getOperation(byOperationId: ack.operationId)?.syncStatus == .gatewaySynced
        switch ack.stage {
        case .peerStored:
            if alreadyCommitted { break }
            operationRepository.markStatus(operationId: ack.operationId, status: .peerRelayed)
            messageRepository.updateStatus(id: targetEntityId, status: .relayed)
        case .backendCommitted:
            operationRepository.markStatus(operationId: ack.operationId, status: .gatewaySynced)
            messageRepository.updateStatus(id: targetEntityId, status: .synced)
        case .recipientAcknowledged:
            if alreadyCommitted { break }
            operationRepository.markStatus(operationId: ack.operationId, status: .peerRelayed)
            messageRepository.updateStatus(id: targetEntityId, status: .delivered)
            // Destination reached: remove from pending retry queue
            messageQueue.remove(operationId: ack.operationId)
        }

        onAckReceived?(ack)

        // If local node is NOT the final destination of the ACK, forward it along the reverse path!
        if !isDestinationForAck && acknowledgementManager.shouldForwardAck(envelope: envelope, localNodeId: localNodeId) {
            forwardAckAlongReversePath(envelope: envelope, ack: ack, incomingFromPeer: fromPeer)
        }
    }

    // MARK: - Forwarding & Multi-Hop Relay

    private func forwardRelayPacket(envelope: ContractV1.Envelope, incomingFromPeer: String, op: ContractV1.Operation) {
        let relayEnvelope = relayManager.prepareRelayEnvelope(envelope: envelope)

        guard let transport = transportDelegate else { return }
        let connected = transport.getConnectedPeers()

        // Exclude incoming peer and source node from relay targets
        let excludeSet: Set<String> = [incomingFromPeer, envelope.sourceNodeId]

        if envelope.destinationNodeId == "*" || envelope.destinationNodeId.caseInsensitiveCompare(ContractV1.broadcastRecipientId) == .orderedSame {
            // Broadcast / SOS: Forward to ALL eligible connected peers (excluding sender)
            let eligible = connected.filter { !excludeSet.contains($0.id) && !excludeSet.contains($0.displayName) }
            guard !eligible.isEmpty else { return }

            guard let data = try? JSONEncoder().encode(relayEnvelope) else { return }
            let peerIds = eligible.map(\.id)
            _ = transport.transmitPacketData(data, toPeers: peerIds)

            onDiagnosticLog?(.tx, "Relayed SOS [\(op.entityId.prefix(8))] to \(eligible.count) peer(s) (hop \(relayEnvelope.hopCount))")
            networkAnalyzer.recordEvent(
                type: .packetForwarded,
                messageId: op.entityId,
                sourceNode: localNodeId,
                targetNode: peerIds.joined(separator: ","),
                explanation: "Relayed broadcast SOS to \(eligible.count) peer(s) at hop \(relayEnvelope.hopCount)"
            )
        } else {
            // Targeted message: Select best next-hop relay candidate
            guard let nextHop = routingEngine.selectNextHop(for: relayEnvelope, among: connected, excluding: excludeSet) else {
                onDiagnosticLog?(.tx, "No suitable next-hop relay found for destination [\(envelope.destinationNodeId.prefix(8))]")
                return
            }

            guard let data = try? JSONEncoder().encode(relayEnvelope) else { return }
            let res = transport.transmitPacketData(data, toPeers: [nextHop.id])

            switch res {
            case .success:
                let score = routingEngine.calculateRelayScore(for: nextHop)
                routingEngine.recordDeliveryAttempt(peerId: nextHop.id, success: true)
                onDiagnosticLog?(.tx, "Forwarded packet [\(relayEnvelope.packetId.prefix(8))] to next hop [\(nextHop.displayName)] (Score: \(String(format: "%.1f", score.totalScore)))")
                networkAnalyzer.recordEvent(
                    type: .packetForwarded,
                    messageId: op.entityId,
                    sourceNode: localNodeId,
                    targetNode: nextHop.displayName,
                    explanation: "Forwarded message to next hop [\(nextHop.displayName)] with score \(String(format: "%.1f", score.totalScore))"
                )
            case .failure(let err):
                routingEngine.recordDeliveryAttempt(peerId: nextHop.id, success: false)
                onDiagnosticLog?(.error, "Forwarding to [\(nextHop.displayName)] failed: \(err)")
                networkAnalyzer.recordEvent(
                    type: .forwardingFailed,
                    messageId: op.entityId,
                    sourceNode: localNodeId,
                    targetNode: nextHop.displayName,
                    explanation: "Forwarding failed to [\(nextHop.displayName)]: \(err.localizedDescription)"
                )
            }
        }
    }

    private func forwardAckAlongReversePath(envelope: ContractV1.Envelope, ack: ContractV1.Acknowledgment, incomingFromPeer: String) {
        let forwardAckEnvelope = acknowledgementManager.prepareForwardedAck(envelope: envelope)

        guard let transport = transportDelegate else { return }
        let connected = transport.getConnectedPeers()

        // 1. Look up reverse route
        let targetPeer: String?
        if let reverseInfo = acknowledgementManager.getReverseRoute(operationId: ack.operationId) {
            targetPeer = reverseInfo.previousHopPeer
        } else {
            // Fallback: select next hop towards envelope destination
            targetPeer = routingEngine.selectNextHop(for: forwardAckEnvelope, among: connected, excluding: [incomingFromPeer])?.id
        }

        guard let nextHopId = targetPeer,
              let targetPeerObj = connected.first(where: { $0.id == nextHopId || $0.displayName == nextHopId }) else {
            onDiagnosticLog?(.ack, "Could not resolve reverse route for ACK [\(ack.operationId.prefix(8))]; awaiting reconnection")
            return
        }

        guard let data = try? JSONEncoder().encode(forwardAckEnvelope) else { return }
        let res = transport.transmitPacketData(data, toPeers: [targetPeerObj.id])

        switch res {
        case .success:
            onDiagnosticLog?(.ack, "Forwarded \(ack.stage.rawValue) ACK for [\(ack.operationId.prefix(8))] along reverse path to [\(targetPeerObj.displayName)]")
            networkAnalyzer.recordEvent(
                type: .ackForwarded,
                messageId: ack.operationId,
                sourceNode: localNodeId,
                targetNode: targetPeerObj.displayName,
                explanation: "Forwarded \(ack.stage.rawValue) ACK towards origin along reverse path"
            )
        case .failure(let err):
            onDiagnosticLog?(.error, "Failed to forward ACK to [\(targetPeerObj.displayName)]: \(err)")
        }
    }

    private func sendAppropriateAck(
        for op: ContractV1.Operation,
        packetId: String,
        toPeer: String,
        envelope: ContractV1.Envelope
    ) {
        let isDestination = (envelope.destinationNodeId.caseInsensitiveCompare(localNodeId) == .orderedSame)
        let ackEnvelope: ContractV1.Envelope

        if isDestination {
            ackEnvelope = acknowledgementManager.createRecipientAck(
                for: op,
                packetId: packetId,
                localNodeId: localNodeId,
                destinationNodeId: envelope.sourceNodeId
            )
        } else {
            ackEnvelope = acknowledgementManager.createPeerStoredAck(
                for: op,
                packetId: packetId,
                localNodeId: localNodeId,
                destinationNodeId: envelope.sourceNodeId
            )
        }

        guard let ackData = try? JSONEncoder().encode(ackEnvelope) else { return }
        _ = transportDelegate?.transmitPacketData(ackData, toPeers: [toPeer])
        onDiagnosticLog?(.ack, "Dispatched \(isDestination ? "RECIPIENT_ACKNOWLEDGED" : "PEER_STORED") ACK for [\(op.operationId.prefix(8))] to [\(toPeer)]")
    }

    private func dispatchEnvelope(_ envelope: ContractV1.Envelope, messageId: String, operationId: String) -> Bool {
        guard let transport = transportDelegate else { return false }
        let connected = transport.getConnectedPeers()
        guard !connected.isEmpty else {
            onDiagnosticLog?(.tx, "No connected peers. Message [\(messageId.prefix(8))] queued locally in SQLite")
            messageRepository.updateStatus(id: messageId, status: .queued)
            operationRepository.markStatus(operationId: operationId, status: .queued)
            return false
        }

        guard let packetData = try? JSONEncoder().encode(envelope) else {
            messageRepository.updateStatus(id: messageId, status: .failed)
            operationRepository.markStatus(operationId: operationId, status: .failed)
            return false
        }

        let res = transport.transmitPacketData(packetData, toPeers: nil)
        switch res {
        case .success(let count):
            if let currentMsg = messageRepository.getMessage(id: messageId), currentMsg.status == .delivered {
                // Already delivered by return ACK during dispatch
            } else {
                messageRepository.updateStatus(id: messageId, status: .relayed)
                operationRepository.markStatus(operationId: operationId, status: .peerRelayed)
            }
            onDiagnosticLog?(.tx, "Dispatched envelope [\(envelope.packetId.prefix(8))] to \(count) peer(s)")
            return true
        case .failure(let err):
            messageRepository.updateStatus(id: messageId, status: .failed)
            operationRepository.markStatus(operationId: operationId, status: .failed)
            onDiagnosticLog?(.error, "Dispatch failed: \(err)")
            return false
        }
    }

    // MARK: - Topology Changes & Dynamic Route Recovery

    public func handlePeerConnected(peer: DiscoveredPeer) {
        routingEngine.recordPeerConnected(peerId: peer.id)
        networkAnalyzer.recordEvent(
            type: .peerConnected,
            sourceNode: localNodeId,
            targetNode: peer.displayName,
            explanation: "Peer [\(peer.displayName)] connected; triggering pending queue evaluation"
        )

        // Evaluate and flush pending messages
        flushPendingQueue()
    }

    public func handlePeerDisconnected(peerId: String) {
        routingEngine.recordPeerDisconnected(peerId: peerId)

        guard let transport = transportDelegate else { return }
        let remainingConnected = transport.getConnectedPeers().filter { $0.id != peerId && $0.displayName != peerId }

        networkAnalyzer.recordEvent(
            type: .peerDisconnected,
            sourceNode: localNodeId,
            targetNode: peerId,
            explanation: "Peer [\(peerId)] disconnected. Active connected peers remaining: \(remainingConnected.count)"
        )

        // Perform dynamic route recovery for pending items
        performRouteRecovery(failedPeerId: peerId, availablePeers: remainingConnected)
    }

    private func performRouteRecovery(failedPeerId: String, availablePeers: [DiscoveredPeer]) {
        let pending = messageQueue.allItems
        guard !pending.isEmpty else { return }

        for item in pending {
            if let targetPeer = routingEngine.findAlternativeRoute(
                for: ContractV1.Envelope(
                    version: 1,
                    packetId: UUID().uuidString.lowercased(),
                    sourceNodeId: localNodeId,
                    destinationNodeId: item.message?.recipientId ?? "*",
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    ttl: 5,
                    hopCount: 0,
                    type: .syncOp,
                    payload: .syncOp(ContractV1.Operation(
                        schemaVersion: 1,
                        operationId: item.operation.id,
                        originNodeId: localNodeId,
                        entityId: item.operation.entityId,
                        timestamp: Int64(item.operation.timestamp.timeIntervalSince1970 * 1000),
                        lamportClock: item.operation.lamportClock,
                        entityType: item.operation.entityType == .sos ? .sos : .message,
                        action: .create,
                        payload: nil
                    ))
                ),
                among: availablePeers,
                excluding: [failedPeerId]
            ) {
                let score = routingEngine.calculateRelayScore(for: targetPeer)
                let explanation = networkAnalyzer.explainRouteRecovery(
                    failedPeer: failedPeerId,
                    chosenPeer: targetPeer,
                    score: score,
                    messageId: item.operation.entityId,
                    isEmergency: item.priority <= .p1EmergencyAck
                )
                onDiagnosticLog?(.session, explanation)
                networkAnalyzer.recordEvent(
                    type: .alternativeRouteSelected,
                    messageId: item.operation.entityId,
                    sourceNode: localNodeId,
                    targetNode: targetPeer.displayName,
                    explanation: explanation
                )
                // Attempt dispatch to the alternative peer
                if let msg = item.message {
                    submitOutboundMessage(msg, operationId: item.operation.id)
                }
            } else {
                onDiagnosticLog?(.session, "No alternative peer available for [\(item.operation.entityId.prefix(8))]; preserved safely in persistent SQLite queue")
            }
        }
    }

    public func flushPendingQueue() {
        guard let transport = transportDelegate, !transport.getConnectedPeers().isEmpty else { return }
        while let item = messageQueue.dequeueNextEligible() {
            if let msg = item.message {
                submitOutboundMessage(msg, operationId: item.operation.id)
            }
        }
    }
}
