import Foundation

public protocol MessageRepositoryProtocol: Sendable {
    func getMessages() -> [OFFGRIDMessage]
    func getMessage(id: String) -> OFFGRIDMessage?
    func saveMessage(_ message: OFFGRIDMessage)
    func updateStatus(id: String, status: MessageDeliveryStatus)
    @discardableResult
    func saveMessageWithOperation(message: OFFGRIDMessage, operation: OFFGRIDOperation) throws -> SQLiteDatabase.OperationInsertionResult
}

public final class MessageRepository: MessageRepositoryProtocol {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
    }

    public func getMessages() -> [OFFGRIDMessage] {
        return database.fetchMessages()
    }

    public func getMessage(id: String) -> OFFGRIDMessage? {
        return database.getMessage(byId: id)
    }

    public func saveMessage(_ message: OFFGRIDMessage) {
        database.insertMessage(message)
    }

    public func updateStatus(id: String, status: MessageDeliveryStatus) {
        database.updateMessageStatus(id: id, status: status)
    }

    @discardableResult
    public func saveMessageWithOperation(message: OFFGRIDMessage, operation: OFFGRIDOperation) throws -> SQLiteDatabase.OperationInsertionResult {
        return try database.saveMessageWithOperation(message: message, operation: operation)
    }
}
