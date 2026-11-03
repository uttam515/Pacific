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

        let sosMessage = OFFGRIDMessage(
            senderId: nodeId,
            senderName: "SOS-NODE-\(String(nodeId.prefix(4)))",
            recipientId: "*",
            content: content,
            type: .sos,
            status: .pending
        )

        // 1. Save to SQLite
        messageRepository.saveMessage(sosMessage)

        // 2. Add to Operation Queue
        if let json = try? JSONEncoder().encode(sosMessage), let jsonString = String(data: json, encoding: .utf8) {
            let op = OFFGRIDOperation(
                entityType: .sos,
                entityId: sosMessage.id,
                action: .create,
                originNodeId: nodeId,
                payloadJson: jsonString,
                syncStatus: .localOnly
            )
            operationRepository.enqueue(operation: op)
        }

        // 3. High-Priority Transport Broadcast
        transportManager?.broadcastMessage(sosMessage)

        self.isBroadcasting = true
        self.broadcastSuccessMessage = "Emergency beacon broadcasted to all nearby mesh peers!"
    }
}
