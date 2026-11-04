import Foundation
import SwiftUI

@MainActor
public final class SyncViewModel: ObservableObject {
    @Published public var pendingOperations: [OFFGRIDOperation] = []
    @Published public var isSyncing: Bool = false

    private let operationRepository: OperationQueueRepository

    public init(
        operationRepository: OperationQueueRepository = OperationQueueRepository()
    ) {
        self.operationRepository = operationRepository
        loadOperations()
    }

    public func loadOperations() {
        self.pendingOperations = operationRepository.getPendingOperations()
    }

    public func triggerManualSync(using gateway: GatewayManager) {
        isSyncing = true
        Task {
            await gateway.sync()
            loadOperations()
            isSyncing = false
        }
    }
}
