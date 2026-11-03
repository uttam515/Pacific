import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [OFFGRIDMessage] = []
    @Published public var inputMessage: String = ""

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private var transportManager: TransportManager?

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadMessages()
    }

    public func configureTransport(_ transport: TransportManager) {
        self.transportManager = transport
    }

    public func loadMessages() {
        self.messages = messageRepository.getMessages().filter { $0.type == .chat }
    }

    public func sendMessage() {
        let trimmed = inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Generate unique operation ID & Message
        let messageId = UUID().uuidString
        let nodeId = KeychainHelper.shared.getOrCreateNodeId()

        var message = OFFGRIDMessage(
            id: messageId,
            senderId: nodeId,
            senderName: "Me (\(String(nodeId.prefix(6))))",
            recipientId: "*",
            content: trimmed,
            type: .chat,
            status: .pending
        )

        // 2. Save directly to SQLite (Local-first persistence)
        messageRepository.saveMessage(message)

        // 3. Update UI immediately
        messages.append(message)
        inputMessage = ""

        // 4. Add to pending operation queue
        if let json = try? JSONEncoder().encode(message), let jsonString = String(data: json, encoding: .utf8) {
            let op = OFFGRIDOperation(
                entityType: .message,
                entityId: message.id,
                action: .create,
                originNodeId: nodeId,
                payloadJson: jsonString,
                syncStatus: .localOnly
            )
            operationRepository.enqueue(operation: op)
        }

        // 5. Attempt peer transmission
        transportManager?.broadcastMessage(message)
    }
}
