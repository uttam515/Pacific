import Foundation
import SwiftUI

@MainActor
public final class SOSViewModel: ObservableObject {
    @Published public var emergencyDetails: String = ""
    @Published public var selectedEmergencyType: String = "Medical Emergency"
    @Published public var isBroadcasting: Bool = false
    @Published public var broadcastSuccessMessage: String?

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

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
    }

    public func configureTransport(_ transport: TransportManager) {
        self.transportManager = transport
    }

    public func broadcastSOS() {
        let nodeId = KeychainHelper.shared.getOrCreateNodeId()
        let content = "[\(selectedEmergencyType.uppercased())] \(emergencyDetails.isEmpty ? "Assistance requested immediately." : emergencyDetails)"
        let messageId = UUID().uuidString
        let operationId = UUID().uuidString

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

        guard let json = try? JSONEncoder().encode(sosMessage),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }

        let op = OFFGRIDOperation(
            id: operationId,
            entityType: .sos,
            entityId: sosMessage.id,
            action: .create,
            originNodeId: nodeId,
            timestamp: Date(),
            lamportClock: sosMessage.lamportClock,
            payloadJson: jsonString,
            syncStatus: .localOnly
        )

        // 1. Atomically persist message & operation to SQLite
        do {
            try messageRepository.saveMessageWithOperation(message: sosMessage, operation: op)
        } catch {
            print("[SOSViewModel] Failed to persist SOS message: \(error)")
            return
        }

        // 2. High-Priority Transport Broadcast
        transportManager?.broadcastPersistedMessage(sosMessage, operationId: op.id)

        self.isBroadcasting = true
        self.broadcastSuccessMessage = "Emergency beacon saved to SQLite and broadcast to mesh peers!"
    }
}
