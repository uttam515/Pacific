import Foundation
import SQLite3

public final class SQLiteDatabase: @unchecked Sendable {
    public static let shared = SQLiteDatabase()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "org.offgrid.sqlite.queue", qos: .userInitiated)

    public init(inMemory: Bool = false) {
        dbQueue.sync {
            openDatabase(inMemory: inMemory)
            configurePragmas()
            createTables()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    private func openDatabase(inMemory: Bool) {
        let path: String
        if inMemory {
            path = ":memory:"
        } else {
            let fileManager = FileManager.default
            guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                path = "offgrid_local.sqlite"
                return
            }
            path = documentsDir.appendingPathComponent("offgrid_local.sqlite").path
        }

        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("[SQLiteDatabase] Error opening database: \(errmsg)")
        } else {
            print("[SQLiteDatabase] Database opened successfully at \(path)")
        }
    }

    private func configurePragmas() {
        execute(sql: "PRAGMA journal_mode = WAL;")
        execute(sql: "PRAGMA synchronous = NORMAL;")
        execute(sql: "PRAGMA foreign_keys = ON;")
    }

    private func createTables() {
        let createMessagesTable = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
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
            id TEXT PRIMARY KEY,
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
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            hardware_platform TEXT NOT NULL,
            is_gateway INTEGER NOT NULL,
            last_seen REAL NOT NULL,
            battery_level REAL
        );
        """

        execute(sql: createMessagesTable)
        execute(sql: createOperationsTable)
        execute(sql: createNodesTable)
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

    // MARK: - Message Operations

    public func insertMessage(_ message: OFFGRIDMessage) {
        dbQueue.sync {
            let sql = """
            INSERT OR REPLACE INTO messages
            (id, sender_id, sender_name, recipient_id, content, type, timestamp, status, hop_count, lamport_clock)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
    }

    public func fetchMessages() -> [OFFGRIDMessage] {
        return dbQueue.sync {
            var messages: [OFFGRIDMessage] = []
            let sql = "SELECT id, sender_id, sender_name, recipient_id, content, type, timestamp, status, hop_count, lamport_clock FROM messages ORDER BY timestamp ASC;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let cId = sqlite3_column_text(statement, 0),
                          let cSenderId = sqlite3_column_text(statement, 1),
                          let cSenderName = sqlite3_column_text(statement, 2),
                          let cRecipientId = sqlite3_column_text(statement, 3),
                          let cContent = sqlite3_column_text(statement, 4),
                          let cType = sqlite3_column_text(statement, 5),
                          let cStatus = sqlite3_column_text(statement, 7) else {
                        continue
                    }

                    let id = String(cString: cId)
                    let senderId = String(cString: cSenderId)
                    let senderName = String(cString: cSenderName)
                    let recipientId = String(cString: cRecipientId)
                    let content = String(cString: cContent)
                    let type = MessageType(rawValue: String(cString: cType)) ?? .chat
                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                    let status = MessageDeliveryStatus(rawValue: String(cString: cStatus)) ?? .pending
                    let hopCount = Int(sqlite3_column_int(statement, 8))
                    let lamportClock = sqlite3_column_int64(statement, 9)

                    let message = OFFGRIDMessage(
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
                    messages.append(message)
                }
            }
            sqlite3_finalize(statement)
            return messages
        }
    }

    // MARK: - Operations Queue

    public func insertOperation(_ op: OFFGRIDOperation) {
        dbQueue.sync {
            let sql = """
            INSERT OR REPLACE INTO operations
            (id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
    }

    public func fetchPendingOperations() -> [OFFGRIDOperation] {
        return dbQueue.sync {
            var ops: [OFFGRIDOperation] = []
            let sql = "SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count FROM operations WHERE sync_status != 'GATEWAY_SYNCED' ORDER BY timestamp ASC;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let cId = sqlite3_column_text(statement, 0),
                          let cEntity = sqlite3_column_text(statement, 1),
                          let cEntityId = sqlite3_column_text(statement, 2),
                          let cAction = sqlite3_column_text(statement, 3),
                          let cOrigin = sqlite3_column_text(statement, 4),
                          let cPayload = sqlite3_column_text(statement, 7),
                          let cStatus = sqlite3_column_text(statement, 8) else {
                        continue
                    }

                    let op = OFFGRIDOperation(
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
                    ops.append(op)
                }
            }
            sqlite3_finalize(statement)
            return ops
        }
    }

    public func updateOperationStatus(id: String, status: SyncStatus) {
        dbQueue.sync {
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
}
