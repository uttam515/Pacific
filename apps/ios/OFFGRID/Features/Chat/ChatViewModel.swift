import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [OFFGRIDMessage] = []
    @Published public var inputMessage: String = ""

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private var transportManager: TransportManager?
    private var cancellables = Set<AnyCancellable>()

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadMessages()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: TransportManager.didUpdateMessagesNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadMessages()
            }
            .store(in: &cancellables)
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

        // 1. Generate unique operation & message IDs (lowercase UUIDv4)
        let messageId = UUID().uuidString.lowercased()
        let operationId = UUID().uuidString.lowercased()
        let nodeId = KeychainHelper.shared.getOrCreateNodeId().lowercased()

        let message = OFFGRIDMessage(
            id: messageId,
            senderId: nodeId,
            senderName: "Me (\(String(nodeId.prefix(6))))",
            recipientId: "*",
            content: trimmed,
            type: .chat,
            timestamp: Date(),
            status: .localOnly
        )

        // 2. Wrap into operation record with Contract v1 payload
        let contractPayload = ContractV1.MessagePayload(text: trimmed, recipientNodeId: ContractV1.broadcastRecipientId)
        guard let json = try? JSONEncoder().encode(contractPayload),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }

        let operation = OFFGRIDOperation(
            id: operationId,
            entityType: .message,
            entityId: message.id,
            action: .create,
            originNodeId: nodeId,
            timestamp: Date(),
            lamportClock: message.lamportClock,
            payloadJson: jsonString,
            syncStatus: .localOnly
        )

        // 3. Atomically persist message & operation in SQLite before transmission
        do {
            try messageRepository.saveMessageWithOperation(message: message, operation: operation)
        } catch {
            print("[ChatViewModel] Failed to persist message atomically: \(error)")
            return
        }

        // 4. Update UI immediately
        messages.append(message)
        inputMessage = ""

        // 5. Attempt transport transmission only after successful local persistence
        if let transport = transportManager {
            transport.broadcastPersistedMessage(message, operationId: operation.id)
            // Refresh updated status (e.g. .relayed or .queued)
            if let updated = messageRepository.getMessage(id: message.id),
               let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updated
            }
        }
    }

    public func retryTransmission(for messageId: String) {
        guard let message = messageRepository.getMessage(id: messageId) else { return }
        let pendingOps = operationRepository.getPendingOperations()
        guard let op = pendingOps.first(where: { $0.entityId.caseInsensitiveCompare(messageId) == .orderedSame }) ?? operationRepository.getOperation(byOperationId: messageId) else {
            return
        }

        operationRepository.incrementRetry(operationId: op.id)
        transportManager?.broadcastPersistedMessage(message, operationId: op.id)
        loadMessages()
    }
}
