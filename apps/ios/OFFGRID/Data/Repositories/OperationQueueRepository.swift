import Foundation

public protocol OperationQueueRepositoryProtocol: Sendable {
    @discardableResult
    func enqueue(operation: OFFGRIDOperation) throws -> SQLiteDatabase.OperationInsertionResult
    func getPendingOperations() -> [OFFGRIDOperation]
    func getOperation(id: String) -> OFFGRIDOperation?
    func getOperation(byOperationId operationId: String) -> OFFGRIDOperation?
    func markStatus(operationId: String, status: SyncStatus)
    func incrementRetry(operationId: String)
}

public final class OperationQueueRepository: OperationQueueRepositoryProtocol {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
    }

    @discardableResult
    public func enqueue(operation: OFFGRIDOperation) throws -> SQLiteDatabase.OperationInsertionResult {
        return try database.insertOperation(operation)
    }

    public func getPendingOperations() -> [OFFGRIDOperation] {
        return database.fetchPendingOperations()
    }

    public func getOperation(id: String) -> OFFGRIDOperation? {
        return database.getOperation(byId: id)
    }

    public func getOperation(byOperationId operationId: String) -> OFFGRIDOperation? {
        return database.getOperation(byOperationId: operationId)
    }

    public func markStatus(operationId: String, status: SyncStatus) {
        database.updateOperationStatus(id: operationId, status: status)
    }

    public func incrementRetry(operationId: String) {
        database.incrementOperationRetry(id: operationId)
    }
}
