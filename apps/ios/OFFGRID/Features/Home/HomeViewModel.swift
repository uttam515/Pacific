import Foundation
import SwiftUI

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var nodeName: String = "My iPhone"
    @Published public var activePeersCount: Int = 0
    @Published public var pendingSyncCount: Int = 0
    @Published public var isGatewayOnline: Bool = false
    @Published public var recentAlerts: [OFFGRIDMessage] = []

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadDashboardStats()
    }

    public func loadDashboardStats() {
        let allMessages = messageRepository.getMessages()
        self.recentAlerts = allMessages.filter { $0.type == .sos }
        self.pendingSyncCount = operationRepository.getPendingOperations().count
    }
}
