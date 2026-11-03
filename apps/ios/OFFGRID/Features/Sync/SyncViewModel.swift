import Foundation
import SwiftUI

@MainActor
public final class SyncViewModel: ObservableObject {
    @Published public var pendingOperations: [OFFGRIDOperation] = []
    @Published public var isSyncing: Bool = false

    private let operationRepository: OperationQueueRepository
    private let syncEngine: SyncEngine

    public init(
        operationRepository: OperationQueueRepository = OperationQueueRepository(),
        syncEngine: SyncEngine = SyncEngine()
    ) {
        self.operationRepository = operationRepository
        self.syncEngine = syncEngine
        loadOperations()
    }

    public func loadOperations() {
        self.pendingOperations = operationRepository.getPendingOperations()
    }

    public func triggerManualSync() {
        isSyncing = true
        Task {
            await syncEngine.syncPendingOperations()
            loadOperations()
            isSyncing = false
        }
    }
}
