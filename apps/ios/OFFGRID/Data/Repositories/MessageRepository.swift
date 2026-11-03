import Foundation

public protocol MessageRepositoryProtocol: Sendable {
    func getMessages() -> [OFFGRIDMessage]
    func saveMessage(_ message: OFFGRIDMessage)
}

public final class MessageRepository: MessageRepositoryProtocol {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase = .shared) {
        self.database = database
    }

    public func getMessages() -> [OFFGRIDMessage] {
        return database.fetchMessages()
    }

    public func saveMessage(_ message: OFFGRIDMessage) {
        database.insertMessage(message)
    }
}
