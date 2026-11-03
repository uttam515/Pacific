import Foundation

public protocol OperationQueueRepositoryProtocol: Sendable {
    func enqueue(operation: OFFGRIDOperation)
    func getPendingOperations() -> [OFFGRIDOperation]
    func getOperation(id: String) -> OFFGRIDOperation?
    func markStatus(operationId: String, status: SyncStatus)
    func incrementRetry(operationId: String)
}

public final class OperationQueueRepository: OperationQueueRepositoryProtocol {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
    }

    public func enqueue(operation: OFFGRIDOperation) {
        database.insertOperation(operation)
    }

    public func getPendingOperations() -> [OFFGRIDOperation] {
        return database.fetchPendingOperations()
    }

    public func getOperation(id: String) -> OFFGRIDOperation? {
        return database.getOperation(byId: id)
    }

    public func markStatus(operationId: String, status: SyncStatus) {
        database.updateOperationStatus(id: operationId, status: status)
    }

    public func incrementRetry(operationId: String) {
        database.incrementOperationRetry(id: operationId)
    }
}
