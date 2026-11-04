import Foundation
import SwiftUI
import Combine

@MainActor
public final class SOSViewModel: ObservableObject {
    @Published public var emergencyDetails: String = ""
    @Published public var selectedEmergencyType: String = "Medical Emergency"
    @Published public var isBroadcasting: Bool = false
    @Published public var broadcastSuccessMessage: String?
    @Published public var outgoingStatus: MessageDeliveryStatus?
    @Published public var activeAlerts: [OFFGRIDMessage] = []
    @Published public var mySentSOS: [OFFGRIDMessage] = []

    public let emergencyTypes = [
        "Medical Emergency",
        "Search & Rescue",
        "Severe Weather / Flood",
        "Fire Hazard",
        "Supplies & Water Needed"
    ]

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private var transportManager: TransportManager?
    private var cancellables = Set<AnyCancellable>()
    private var lastOutgoingMessageId: String?

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadSOSData()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: TransportManager.didUpdateSOSNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadSOSData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: TransportManager.didUpdateMessagesNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadSOSData()
            }
            .store(in: &cancellables)
    }

    public func configureTransport(_ transport: TransportManager) {
        self.transportManager = transport
    }

    public func loadSOSData() {
        let nodeId = KeychainHelper.shared.getOrCreateNodeId()
        let allMessages = messageRepository.getMessages()
        let sosMessages = allMessages.filter { $0.type == .sos }

        self.activeAlerts = sosMessages.filter { $0.senderId.caseInsensitiveCompare(nodeId) != .orderedSame }
            .sorted(by: { $0.timestamp > $1.timestamp })
        self.mySentSOS = sosMessages.filter { $0.senderId.caseInsensitiveCompare(nodeId) == .orderedSame }
            .sorted(by: { $0.timestamp > $1.timestamp })

        // Refresh outgoing status if tracking a recent beacon
        if let lastId = lastOutgoingMessageId,
           let updated = messageRepository.getMessage(id: lastId) {
            self.outgoingStatus = updated.status
            updateStatusMessage(for: updated.status)
        }
    }

    private func updateStatusMessage(for status: MessageDeliveryStatus) {
        switch status {
        case .localOnly:
            self.broadcastSuccessMessage = "Beacon saved to SQLite locally. Awaiting radio dispatch..."
        case .queued:
            self.broadcastSuccessMessage = "No peers connected. Beacon queued in SQLite — will transmit immediately upon connection."
        case .relayed:
            self.broadcastSuccessMessage = "Peer Stored: Durably stored on mesh peer outbox. Relayed on mesh radio."
        case .delivered:
            self.broadcastSuccessMessage = "Recipient Acknowledged: Confirmed received and acknowledged by end recipient."
        case .synced:
            self.broadcastSuccessMessage = "Backend Committed: Synchronized and committed by central gateway."
        case .failed:
            self.broadcastSuccessMessage = "Transmission failed. Tap retry to re-broadcast."
        default:
            break
        }
    }

    public func broadcastSOS() {
        let nodeId = KeychainHelper.shared.getOrCreateNodeId().lowercased()
        let content = "[\(selectedEmergencyType.uppercased())] \(emergencyDetails.isEmpty ? "Assistance requested immediately." : emergencyDetails)"
        let messageId = UUID().uuidString.lowercased()
        let operationId = UUID().uuidString.lowercased()
        self.lastOutgoingMessageId = messageId

        let sosMessage = OFFGRIDMessage(
            id: messageId,
            senderId: nodeId,
            senderName: "SOS-NODE-\(String(nodeId.prefix(4)))",
            recipientId: "*",
            content: content,
            type: .sos,
            timestamp: Date(),
            status: .localOnly
        )

        let category: ContractV1.SOSCategory
        let upper = selectedEmergencyType.uppercased()
        if upper.contains("MEDICAL") {
            category = .medical
        } else if upper.contains("SUPPLIES") {
            category = .supplies
        } else if upper.contains("OTHER") {
            category = .other
        } else {
            category = .assistance
        }
        let contractPayload = ContractV1.SOSPayload(
            text: content,
            category: category,
            location: ContractV1.SOSLocation(label: "Off-Grid Beacon", latitude: nil, longitude: nil)
        )

        guard let json = try? JSONEncoder().encode(contractPayload),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }

        let op = OFFGRIDOperation(
            id: operationId,
            entityType: .sos,
            entityId: sosMessage.id,
            action: .create,
            originNodeId: nodeId,
            timestamp: sosMessage.timestamp,
            lamportClock: sosMessage.lamportClock,
            payloadJson: jsonString,
            syncStatus: .localOnly
        )

        // 1. Atomically persist message & operation to SQLite
        do {
            let canonical = ContractV1.Operation(operationId:operationId,originNodeId:nodeId,entityId:messageId,timestamp:Int64(sosMessage.timestamp.timeIntervalSince1970*1000),lamportClock:sosMessage.lamportClock,entityType:.sos,action:.create,baseVersion:0,payload:.sos(contractPayload))
            let envelope = ContractV1.Envelope(packetId:UUID().uuidString.lowercased(),sourceNodeId:nodeId,destinationNodeId:"*",timestamp:canonical.timestamp,ttl:5,hopCount:0,type:.syncOp,payload:.syncOp(canonical))
            try messageRepository.saveMessageWithOperation(message: sosMessage, operation: op, gatewayEnvelope:envelope)
        } catch {
            print("[SOSViewModel] Failed to persist SOS message: \(error)")
            self.broadcastSuccessMessage = "Failed to persist SOS locally: \(error.localizedDescription)"
            return
        }

        self.isBroadcasting = true
        self.outgoingStatus = .localOnly
        self.broadcastSuccessMessage = "Beacon saved to SQLite locally. Dispatching to radio transport..."

        // 2. High-Priority Transport Broadcast
        if let transport = transportManager {
            let sent = transport.broadcastPersistedMessage(sosMessage, operationId: op.id)
            if sent {
                self.outgoingStatus = .relayed
                self.broadcastSuccessMessage = "Relayed onto local mesh radio hop. Waiting for peer delivery acknowledgment..."
            } else {
                self.outgoingStatus = .queued
                self.broadcastSuccessMessage = "No peers connected. Beacon queued in SQLite — will transmit immediately upon connection."
            }
        } else {
            self.outgoingStatus = .queued
            self.broadcastSuccessMessage = "Transport inactive. Beacon queued locally in SQLite."
        }

        loadSOSData()
    }

    public func retryBroadcast(for messageId: String) {
        guard let message = messageRepository.getMessage(id: messageId) else { return }
        let pendingOps = operationRepository.getPendingOperations()
        if let op = pendingOps.first(where: { $0.entityId.caseInsensitiveCompare(messageId) == .orderedSame }) {
            operationRepository.incrementRetry(operationId: op.id)
            transportManager?.broadcastPersistedMessage(message, operationId: op.id)
        } else if let directOp = operationRepository.getOperation(byOperationId: messageId) {
            operationRepository.incrementRetry(operationId: directOp.id)
            transportManager?.broadcastPersistedMessage(message, operationId: directOp.id)
        }
        loadSOSData()
    }
}
