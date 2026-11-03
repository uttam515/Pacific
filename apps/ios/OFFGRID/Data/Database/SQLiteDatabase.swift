import Foundation
import SQLite3

public final class SQLiteDatabase: @unchecked Sendable {
    public static let shared = SQLiteDatabase()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "org.offgrid.sqlite.queue", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()
    private let currentDatabasePath: String
    private let currentInMemory: Bool

    public init(inMemory: Bool = false, customPath: String? = nil) {
        self.currentInMemory = inMemory
        self.dbQueue.setSpecific(key: queueKey, value: ())

        if inMemory {
            self.currentDatabasePath = ":memory:"
        } else if let customPath = customPath {
            self.currentDatabasePath = customPath
        } else {
            let fileManager = FileManager.default
            guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.currentDatabasePath = "offgrid_local.sqlite"
                self.openAndInitialize()
                return
            }
            self.currentDatabasePath = documentsDir.appendingPathComponent("offgrid_local.sqlite").path
        }
        self.openAndInitialize()
    }

    deinit {
        closeDatabase()
    }

    private func runOnQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try block()
        } else {
            return try dbQueue.sync {
                try block()
            }
        }
    }

    private func openAndInitialize() {
        runOnQueue {
            openDatabase()
            configurePragmas()
            runMigrations()
        }
    }

    public func close() {
        runOnQueue {
            closeDatabase()
        }
    }

    public func reopen() {
        runOnQueue {
            if db == nil {
                openDatabase()
                configurePragmas()
                runMigrations()
            }
        }
    }

    private func closeDatabase() {
        if let db = db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    private func openDatabase() {
        if db != nil { return }
        if sqlite3_open_v2(currentDatabasePath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("[SQLiteDatabase] Error opening database: \(errmsg)")
        } else {
            print("[SQLiteDatabase] Database opened successfully at \(currentDatabasePath)")
        }
    }

    private func configurePragmas() {
        execute(sql: "PRAGMA journal_mode = WAL;")
        execute(sql: "PRAGMA synchronous = NORMAL;")
        execute(sql: "PRAGMA foreign_keys = ON;")
    }

    // MARK: - Schema Migrations

    private func getUserVersion() -> Int {
        var version = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                version = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return version
    }

    private func setUserVersion(_ version: Int) {
        execute(sql: "PRAGMA user_version = \(version);")
    }

    private func runMigrations() {
        let version = getUserVersion()
        if version < 1 {
            applyMigrationV1()
            setUserVersion(1)
        }
    }

    private func applyMigrationV1() {
        let createMessagesTable = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY NOT NULL,
            sender_id TEXT NOT NULL,
            sender_name TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            status TEXT NOT NULL,
            hop_count INTEGER NOT NULL,
            lamport_clock INTEGER NOT NULL
        );
        """

        let createOperationsTable = """
        CREATE TABLE IF NOT EXISTS operations (
            id TEXT PRIMARY KEY NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            action TEXT NOT NULL,
            origin_node_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            lamport_clock INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            retry_count INTEGER NOT NULL
        );
        """

        let createNodesTable = """
        CREATE TABLE IF NOT EXISTS nodes (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            hardware_platform TEXT NOT NULL,
            is_gateway INTEGER NOT NULL,
            last_seen REAL NOT NULL,
            battery_level REAL
        );
        """

        let createMessageIndexes = """
        CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
        CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(type);
        """

        let createOperationIndexes = """
        CREATE INDEX IF NOT EXISTS idx_operations_status_timestamp ON operations(sync_status, timestamp);
        CREATE INDEX IF NOT EXISTS idx_operations_entity ON operations(entity_id);
        """

        execute(sql: createMessagesTable)
        execute(sql: createOperationsTable)
        execute(sql: createNodesTable)
        execute(sql: createMessageIndexes)
        execute(sql: createOperationIndexes)
    }

    public func execute(sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                let message = String(cString: errMsg)
                print("[SQLiteDatabase] Error executing SQL: \(message)")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Transaction Handling

    public func performTransaction<T>(_ block: () throws -> T) throws -> T {
        return try runOnQueue {
            execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
            do {
                let result = try block()
                execute(sql: "COMMIT TRANSACTION;")
                return result
            } catch {
                execute(sql: "ROLLBACK TRANSACTION;")
                throw error
            }
        }
    }

    // MARK: - Atomic Message + Operation Persistence

    public func saveMessageWithOperation(message: OFFGRIDMessage, operation: OFFGRIDOperation) throws {
        try performTransaction {
            insertMessageInternal(message)
            insertOperationInternal(operation)
        }
    }

    // MARK: - Message Operations

    private func insertMessageInternal(_ message: OFFGRIDMessage) {
        let sql = """
        INSERT INTO messages
        (id, sender_id, sender_name, recipient_id, content, type, timestamp, status, hop_count, lamport_clock)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            status = excluded.status,
            hop_count = excluded.hop_count,
            lamport_clock = excluded.lamport_clock;
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (message.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (message.senderId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (message.senderName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (message.recipientId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (message.content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (message.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 7, message.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 8, (message.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 9, Int32(message.hopCount))
            sqlite3_bind_int64(statement, 10, message.lamportClock)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                print("[SQLiteDatabase] Failed to insert message: \(errmsg)")
            }
        }
        sqlite3_finalize(statement)
    }

    public func insertMessage(_ message: OFFGRIDMessage) {
        runOnQueue {
            insertMessageInternal(message)
        }
    }

    public func updateMessageStatus(id: String, status: MessageDeliveryStatus) {
        runOnQueue {
            let sql = "UPDATE messages SET status = ? WHERE id = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (status.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    public func getMessage(byId id: String) -> OFFGRIDMessage? {
        return runOnQueue {
            let sql = "SELECT id, sender_id, sender_name, recipient_id, content, type, timestamp, status, hop_count, lamport_clock FROM messages WHERE id = ? LIMIT 1;"
            var statement: OpaquePointer?
            var message: OFFGRIDMessage?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) == SQLITE_ROW {
                    message = parseMessageRow(statement: statement)
                }
            }
            sqlite3_finalize(statement)
            return message
        }
    }

    public func fetchMessages() -> [OFFGRIDMessage] {
        return runOnQueue {
            var messages: [OFFGRIDMessage] = []
            let sql = "SELECT id, sender_id, sender_name, recipient_id, content, type, timestamp, status, hop_count, lamport_clock FROM messages ORDER BY timestamp ASC;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let message = parseMessageRow(statement: statement) {
                        messages.append(message)
                    }
                }
            }
            sqlite3_finalize(statement)
            return messages
        }
    }

    private func parseMessageRow(statement: OpaquePointer?) -> OFFGRIDMessage? {
        guard let statement = statement,
              let cId = sqlite3_column_text(statement, 0),
              let cSenderId = sqlite3_column_text(statement, 1),
              let cSenderName = sqlite3_column_text(statement, 2),
              let cRecipientId = sqlite3_column_text(statement, 3),
              let cContent = sqlite3_column_text(statement, 4),
              let cType = sqlite3_column_text(statement, 5),
              let cStatus = sqlite3_column_text(statement, 7) else {
            return nil
        }

        let id = String(cString: cId)
        let senderId = String(cString: cSenderId)
        let senderName = String(cString: cSenderName)
        let recipientId = String(cString: cRecipientId)
        let content = String(cString: cContent)
        let type = MessageType(rawValue: String(cString: cType)) ?? .chat
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        let status = MessageDeliveryStatus(rawValue: String(cString: cStatus)) ?? .localOnly
        let hopCount = Int(sqlite3_column_int(statement, 8))
        let lamportClock = sqlite3_column_int64(statement, 9)

        return OFFGRIDMessage(
            id: id,
            senderId: senderId,
            senderName: senderName,
            recipientId: recipientId,
            content: content,
            type: type,
            timestamp: timestamp,
            status: status,
            hopCount: hopCount,
            lamportClock: lamportClock
        )
    }

    // MARK: - Operations Queue

    private func insertOperationInternal(_ op: OFFGRIDOperation) {
        let sql = """
        INSERT INTO operations
        (id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (op.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (op.entityType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (op.entityId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (op.action.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (op.originNodeId as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 6, op.timestamp.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 7, op.lamportClock)
            sqlite3_bind_text(statement, 8, (op.payloadJson as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 9, (op.syncStatus.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 10, Int32(op.retryCount))

            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                print("[SQLiteDatabase] Failed to insert operation: \(errmsg)")
            }
        }
        sqlite3_finalize(statement)
    }

    public func insertOperation(_ op: OFFGRIDOperation) {
        runOnQueue {
            insertOperationInternal(op)
        }
    }

    public func getOperation(byId id: String) -> OFFGRIDOperation? {
        return runOnQueue {
            let sql = "SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count FROM operations WHERE id = ? LIMIT 1;"
            var statement: OpaquePointer?
            var op: OFFGRIDOperation?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) == SQLITE_ROW {
                    op = parseOperationRow(statement: statement)
                }
            }
            sqlite3_finalize(statement)
            return op
        }
    }

    public func fetchPendingOperations() -> [OFFGRIDOperation] {
        return runOnQueue {
            var ops: [OFFGRIDOperation] = []
            let sql = "SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count FROM operations WHERE sync_status != 'GATEWAY_SYNCED' ORDER BY timestamp ASC;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let op = parseOperationRow(statement: statement) {
                        ops.append(op)
                    }
                }
            }
            sqlite3_finalize(statement)
            return ops
        }
    }

    public func updateOperationStatus(id: String, status: SyncStatus) {
        runOnQueue {
            let sql = "UPDATE operations SET sync_status = ? WHERE id = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (status.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    public func incrementOperationRetry(id: String) {
        runOnQueue {
            let sql = "UPDATE operations SET retry_count = retry_count + 1 WHERE id = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    private func parseOperationRow(statement: OpaquePointer?) -> OFFGRIDOperation? {
        guard let statement = statement,
              let cId = sqlite3_column_text(statement, 0),
              let cEntity = sqlite3_column_text(statement, 1),
              let cEntityId = sqlite3_column_text(statement, 2),
              let cAction = sqlite3_column_text(statement, 3),
              let cOrigin = sqlite3_column_text(statement, 4),
              let cPayload = sqlite3_column_text(statement, 7),
              let cStatus = sqlite3_column_text(statement, 8) else {
            return nil
        }

        return OFFGRIDOperation(
            id: String(cString: cId),
            entityType: OperationEntity(rawValue: String(cString: cEntity)) ?? .message,
            entityId: String(cString: cEntityId),
            action: OperationAction(rawValue: String(cString: cAction)) ?? .create,
            originNodeId: String(cString: cOrigin),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            lamportClock: sqlite3_column_int64(statement, 6),
            payloadJson: String(cString: cPayload),
            syncStatus: SyncStatus(rawValue: String(cString: cStatus)) ?? .localOnly,
            retryCount: Int(sqlite3_column_int(statement, 9))
        )
    }
}
