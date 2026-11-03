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
            do {
                try performTransaction {
                    applyMigrationV1()
                    setUserVersion(1)
                }
            } catch {
                print("[SQLiteDatabase] Migration v1 failed: \(error)")
            }
        }
        if getUserVersion() < 2 {
            do {
                try performTransaction {
                    try applyMigrationV2()
                    setUserVersion(2)
                }
            } catch {
                print("[SQLiteDatabase] Migration v2 failed: \(error)")
            }
        }
    }

    public func tableHasColumn(table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        var found = false
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cName = sqlite3_column_text(statement, 1) {
                    if String(cString: cName) == column {
                        found = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        return found
    }

    // Fault injection hook for testing migration atomicity
    public static var migrationV2FaultInjection: (() throws -> Void)?

    public struct OperationCollisionDiagnostic: CustomStringConvertible, Sendable {
        public let operationId: String
        public let count: Int
        public let distinctPayloads: Int

        public var description: String {
            return "Collision on operation_id '\(operationId)': \(count) records, \(distinctPayloads) distinct payloads."
        }
    }

    public enum MigrationError: Error, LocalizedError {
        case collisionDetected([OperationCollisionDiagnostic])
        case migrationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .collisionDetected(let diags):
                return "Migration v2 aborted: Unresolved legacy collisions detected without data loss:\n" +
                    diags.map { "  - \($0.description)" }.joined(separator: "\n")
            case .migrationFailed(let msg):
                return "Migration failed: \(msg)"
            }
        }
    }

    private func checkForCollisions(column: String) throws {
        let sql = """
        SELECT \(column), COUNT(*), COUNT(DISTINCT payload_json)
        FROM operations
        GROUP BY \(column) COLLATE NOCASE
        HAVING COUNT(*) > 1;
        """
        var statement: OpaquePointer?
        var diagnostics: [OperationCollisionDiagnostic] = []
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let opId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
                let cnt = Int(sqlite3_column_int(statement, 1))
                let distinctPayloads = Int(sqlite3_column_int(statement, 2))
                diagnostics.append(OperationCollisionDiagnostic(operationId: opId, count: cnt, distinctPayloads: distinctPayloads))
            }
        }
        sqlite3_finalize(statement)

        if !diagnostics.isEmpty {
            throw MigrationError.collisionDetected(diagnostics)
        }
    }

    private func applyMigrationV2() throws {
        // Step 1: Pre-migration collision detection on legacy `id`
        // If collisions exist, abort migration immediately without deleting or mutating any data
        try checkForCollisions(column: "id")

        // Step 2: Add additive Contract v1 columns with column existence checks
        if !tableHasColumn(table: "operations", column: "operation_id") {
            try executeOrThrow(sql: "ALTER TABLE operations ADD COLUMN operation_id TEXT COLLATE NOCASE;")
        }
        if !tableHasColumn(table: "operations", column: "base_version") {
            try executeOrThrow(sql: "ALTER TABLE operations ADD COLUMN base_version INTEGER DEFAULT 0;")
        }
        if !tableHasColumn(table: "operations", column: "schema_version") {
            try executeOrThrow(sql: "ALTER TABLE operations ADD COLUMN schema_version INTEGER DEFAULT 1;")
        }

        // Step 3: Trigger fault injection hook if active (for atomicity verification)
        if let fault = SQLiteDatabase.migrationV2FaultInjection {
            try fault()
        }

        // Step 4: Backfill legacy IDs without altering casing (preserving exact identities)
        try executeOrThrow(sql: "UPDATE operations SET operation_id = id WHERE operation_id IS NULL OR operation_id = '';")

        // Step 5: Post-backfill collision check on operation_id
        try checkForCollisions(column: "operation_id")

        // Step 6: Create UNIQUE index only after verifying data is 100% clean
        try executeOrThrow(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_operations_operation_id ON operations(operation_id COLLATE NOCASE);")
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

    public func executeOrThrow(sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg != nil ? String(cString: errMsg!) : "Unknown SQLite error"
            sqlite3_free(errMsg)
            throw NSError(domain: "org.offgrid.sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
            try insertOperationInternal(operation)
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

    public enum OperationInsertionResult: Equatable, Sendable {
        case inserted
        case duplicateIdentical
    }

    public enum OperationStorageError: Error, LocalizedError, Equatable {
        case conflictingPayload(operationId: String, existingPayload: String, newPayload: String)
        case databaseError(String)

        public var errorDescription: String? {
            switch self {
            case .conflictingPayload(let opId, let existing, let new):
                return "Integrity conflict: Operation ID '\(opId)' already exists with conflicting content. Existing: '\(existing)', New: '\(new)'."
            case .databaseError(let msg):
                return "Database error: \(msg)"
            }
        }
    }

    public func getOperationInternal(byIdOrOpId id: String) -> OFFGRIDOperation? {
        let sql = """
        SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count
        FROM operations
        WHERE id = ? COLLATE NOCASE OR (operation_id IS NOT NULL AND operation_id = ? COLLATE NOCASE)
        LIMIT 1;
        """
        var statement: OpaquePointer?
        var op: OFFGRIDOperation?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                op = parseOperationRow(statement: statement)
            }
        }
        sqlite3_finalize(statement)
        return op
    }

    @discardableResult
    private func insertOperationInternal(_ op: OFFGRIDOperation) throws -> OperationInsertionResult {
        // 1. Detect existing record under this operation ID (case-insensitively)
        if let existing = getOperationInternal(byIdOrOpId: op.id) {
            let sameEntity = existing.entityType == op.entityType
            let sameEntityId = existing.entityId.caseInsensitiveCompare(op.entityId) == .orderedSame
            let sameAction = existing.action == op.action
            let sameOrigin = existing.originNodeId.caseInsensitiveCompare(op.originNodeId) == .orderedSame
            let samePayload = existing.payloadJson == op.payloadJson

            if sameEntity && sameEntityId && sameAction && sameOrigin && samePayload {
                // Exact identical duplicate: safe idempotent no-op
                return .duplicateIdentical
            } else {
                // Conflicting payload under existing ID: abort with explicit integrity error
                throw OperationStorageError.conflictingPayload(
                    operationId: op.id,
                    existingPayload: existing.payloadJson,
                    newPayload: op.payloadJson
                )
            }
        }

        // 2. Insert new operation with standard INSERT INTO
        let sql = """
        INSERT INTO operations
        (id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count, operation_id, base_version, schema_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_text(statement, 11, (op.id as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 12, 0)
            sqlite3_bind_int(statement, 13, 1)

            let stepRes = sqlite3_step(statement)
            if stepRes != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw OperationStorageError.databaseError("Failed to insert operation: \(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw OperationStorageError.databaseError("Failed to prepare insert statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return .inserted
    }

    @discardableResult
    public func insertOperation(_ op: OFFGRIDOperation) throws -> OperationInsertionResult {
        return try runOnQueue {
            return try insertOperationInternal(op)
        }
    }

    public func getOperation(byId id: String) -> OFFGRIDOperation? {
        return runOnQueue {
            let sql = "SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count FROM operations WHERE id = ? COLLATE NOCASE LIMIT 1;"
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

    public func getOperation(byOperationId operationId: String) -> OFFGRIDOperation? {
        return runOnQueue {
            let sql = "SELECT id, entity_type, entity_id, action, origin_node_id, timestamp, lamport_clock, payload_json, sync_status, retry_count FROM operations WHERE operation_id = ? COLLATE NOCASE LIMIT 1;"
            var statement: OpaquePointer?
            var op: OFFGRIDOperation?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (operationId as NSString).utf8String, -1, nil)
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
