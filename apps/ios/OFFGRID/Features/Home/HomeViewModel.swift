import Foundation
import SwiftUI
import Combine

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var nodeName: String = "My iPhone"
    @Published public var activePeersCount: Int = 0
    @Published public var pendingSyncCount: Int = 0
    @Published public var isGatewayOnline: Bool = false
    @Published public var recentAlerts: [OFFGRIDMessage] = []

    private let messageRepository: MessageRepository
    private let operationRepository: OperationQueueRepository
    private var cancellables = Set<AnyCancellable>()

    public init(
        messageRepository: MessageRepository = MessageRepository(),
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.messageRepository = messageRepository
        self.operationRepository = operationRepository
        loadDashboardStats()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: TransportManager.didUpdateSOSNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadDashboardStats()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: TransportManager.didUpdateMessagesNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadDashboardStats()
            }
            .store(in: &cancellables)
    }

    public func loadDashboardStats() {
        let allMessages = messageRepository.getMessages()
        self.recentAlerts = allMessages.filter { $0.type == .sos }
            .sorted(by: { $0.timestamp > $1.timestamp })
        self.pendingSyncCount = operationRepository.getPendingOperations().count
    }
}
