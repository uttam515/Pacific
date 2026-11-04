import Foundation
import SQLite3

public final class ContractV1FixtureTests {
    
    public init() {}
    
    public func runAllTests() -> (passed: Int, total: Int) {
        print("\n===========================================")
        print("  OFFGRID iOS Contract v1 Fixture Tests   ")
        print("===========================================")
        
        var passedCount = 0
        let totalCount = 7
        
        if testAllSharedFixtures() { passedCount += 1 }
        if testSQLiteV2AdditiveMigration() { passedCount += 1 }
        if testInstallationIdentityLifecycle() { passedCount += 1 }
        if testOperationIdUniquenessBehavior() { passedCount += 1 }
        if testLegacyCollisionAbortsMigrationSafely() { passedCount += 1 }
        if testFaultInjectedMigrationAtomicityRollback() { passedCount += 1 }
        if testLegacyUppercasePreservation() { passedCount += 1 }
        
        if passedCount == totalCount {
            print("\n===========================================")
            print("  ALL CONTRACT V1 FIXTURE TESTS PASSED! (\(passedCount)/\(totalCount))")
            print("===========================================")
        } else {
            print("\n[FAILURE] CONTRACT V1 TESTS FAILED: \(passedCount)/\(totalCount) passed")
        }
        
        return (passed: passedCount, total: totalCount)
    }
    
    // MARK: - 1. Shared Protocol Fixtures (33 total: 26 valid, 7 invalid)
    
    public func testAllSharedFixtures() -> Bool {
        print("\n[RUNNING] 1. Shared Contract v1 Fixtures Validation (33 fixtures)...")
        
        let manifestPaths = [
            "packages/protocol/fixtures/v1/manifest.json",
            "../packages/protocol/fixtures/v1/manifest.json",
            "../../packages/protocol/fixtures/v1/manifest.json"
        ]
        
        var manifestUrl: URL?
        for path in manifestPaths {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) {
                manifestUrl = u
                break
            }
        }
        
        guard let url = manifestUrl,
              let manifestData = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let fixtures = manifest["fixtures"] as? [String: [String: Any]] else {
            print("[FAIL] Cannot locate or parse manifest.json")
            return false
        }
        
        let fixturesDir = url.deletingLastPathComponent()
        var validCount = 0
        var invalidRejectedCount = 0
        var failed = false
        
        let sortedKeys = fixtures.keys.sorted()
        for filename in sortedKeys {
            let meta = fixtures[filename]!
            let schema = meta["schema"] as! String
            let shouldBeValid = meta["valid"] as! Bool
            let fileUrl = fixturesDir.appendingPathComponent(filename)
            
            guard let fileData = try? Data(contentsOf: fileUrl) else {
                print("  [FAIL] Cannot read fixture file: \(filename)")
                failed = true
                continue
            }
            
            do {
                try ContractV1Validator.validateRawJSON(data: fileData, expectedSchema: schema)
                if shouldBeValid {
                    // Also test semantic round-trip for valid fixtures
                    if testRoundTrip(data: fileData, schema: schema, filename: filename) {
                        validCount += 1
                        print("  [PASS] Valid fixture accepted & round-tripped: \(filename) (\(schema))")
                    } else {
                        print("  [FAIL] Valid fixture failed semantic round-trip: \(filename)")
                        failed = true
                    }
                } else {
                    print("  [FAIL] Invalid fixture unexpectedly accepted: \(filename)")
                    failed = true
                }
            } catch {
                if !shouldBeValid {
                    invalidRejectedCount += 1
                    print("  [PASS] Invalid fixture correctly rejected: \(filename) -> \(error)")
                } else {
                    print("  [FAIL] Valid fixture unexpectedly rejected: \(filename) -> \(error)")
                    failed = true
                }
            }
        }
        
        print("  -> Results: \(validCount) valid accepted, \(invalidRejectedCount) invalid rejected (Total: \(sortedKeys.count))")
        return !failed && (validCount == 26) && (invalidRejectedCount == 7)
    }
    
    private func testRoundTrip(data: Data, schema: String, filename: String) -> Bool {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        
        do {
            switch schema {
            case "Operation":
                let op = try decoder.decode(ContractV1.Operation.self, from: data)
                let encData = try encoder.encode(op)
                let reDecoded = try decoder.decode(ContractV1.Operation.self, from: encData)
                return op == reDecoded
                
            case "Acknowledgment":
                let ack = try decoder.decode(ContractV1.Acknowledgment.self, from: data)
                let encData = try encoder.encode(ack)
                let reDecoded = try decoder.decode(ContractV1.Acknowledgment.self, from: encData)
                return ack == reDecoded
                
            case "Envelope":
                let env = try decoder.decode(ContractV1.Envelope.self, from: data)
                let encData = try encoder.encode(env)
                let reDecoded = try decoder.decode(ContractV1.Envelope.self, from: encData)
                return env == reDecoded
                
            case "PushRequest":
                let req = try decoder.decode(ContractV1.PushRequest.self, from: data)
                let encData = try encoder.encode(req)
                let reDecoded = try decoder.decode(ContractV1.PushRequest.self, from: encData)
                return req == reDecoded
                
            case "PushResponse":
                let res = try decoder.decode(ContractV1.PushResponse.self, from: data)
                let encData = try encoder.encode(res)
                let reDecoded = try decoder.decode(ContractV1.PushResponse.self, from: encData)
                return res == reDecoded
                
            case "PullResponse":
                let res = try decoder.decode(ContractV1.PullResponse.self, from: data)
                let encData = try encoder.encode(res)
                let reDecoded = try decoder.decode(ContractV1.PullResponse.self, from: encData)
                return res == reDecoded
                
            default:
                // Non-core fixtures
                return true
            }
        } catch {
            print("    [RoundTrip Error] \(filename): \(error)")
            return false
        }
    }
    
    // MARK: - 2. Additive SQLite Schema Migration v2
    
    public func testSQLiteV2AdditiveMigration() -> Bool {
        print("\n[RUNNING] 2. Additive SQLite v2 Schema Migration & Data Preservation...")
        
        let testDbPath = "/tmp/offgrid_migration_v2_test_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
            try? FileManager.default.removeItem(atPath: "\(testDbPath)-wal")
            try? FileManager.default.removeItem(atPath: "\(testDbPath)-shm")
        }
        
        // Step A: Manually create a v1 database and insert legacy rows
        var rawDb: OpaquePointer?
        guard sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            print("  [FAIL] Unable to open raw sqlite test file")
            return false
        }
        
        let createV1Tables = """
        PRAGMA user_version = 1;
        CREATE TABLE messages (
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
        CREATE TABLE operations (
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
        INSERT INTO messages VALUES ('msg-legacy-1', 'node-1', 'Alice', 'node-2', 'Hello from v1', 'chat', 1700000000.0, 'DELIVERED', 0, 1);
        INSERT INTO operations VALUES ('op-legacy-1', 'MESSAGE', 'msg-legacy-1', 'CREATE', 'node-1', 1700000000.0, 1, '{"text":"Hello from v1"}', 'QUEUED', 0);
        """
        
        sqlite3_exec(rawDb, createV1Tables, nil, nil, nil)
        sqlite3_close_v2(rawDb)
        
        // Step B: Open using SQLiteDatabase, which automatically triggers runMigrations() -> applyMigrationV2()
        let database = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        
        // Verify user_version includes the additive gateway migration
        var upgradedVersion = 0
        if sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(rawDb, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    upgradedVersion = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
            
            // Verify new columns exist in operations table
            var hasOperationId = false
            var hasBaseVersion = false
            var hasSchemaVersion = false
            var backfilledOperationId: String?
            var backfilledBaseVersion: Int64 = -1
            var backfilledSchemaVersion: Int = -1
            
            if sqlite3_prepare_v2(rawDb, "SELECT operation_id, base_version, schema_version FROM operations WHERE id = 'op-legacy-1';", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    hasOperationId = true
                    hasBaseVersion = true
                    hasSchemaVersion = true
                    if let cText = sqlite3_column_text(stmt, 0) {
                        backfilledOperationId = String(cString: cText)
                    }
                    backfilledBaseVersion = sqlite3_column_int64(stmt, 1)
                    backfilledSchemaVersion = Int(sqlite3_column_int(stmt, 2))
                }
            }
            sqlite3_finalize(stmt)
            sqlite3_close_v2(rawDb)
            
            guard upgradedVersion == 3 else {
                print("  [FAIL] Expected user_version 3, got \(upgradedVersion)")
                return false
            }
            
            guard hasOperationId && hasBaseVersion && hasSchemaVersion else {
                print("  [FAIL] Operations table missing new v2 columns")
                return false
            }
            
            guard backfilledOperationId == "op-legacy-1" else {
                print("  [FAIL] operation_id was not backfilled correctly: \(String(describing: backfilledOperationId))")
                return false
            }
            
            guard backfilledBaseVersion == 0 && backfilledSchemaVersion == 1 else {
                print("  [FAIL] base_version or schema_version default values incorrect")
                return false
            }
        }
        
        // Verify legacy operation is still intact via repository
        let pending = database.fetchPendingOperations()
        guard pending.count == 1, pending.first?.id == "op-legacy-1" else {
            print("  [FAIL] Existing pending operation lost or corrupted")
            return false
        }
        
        let message = database.getMessage(byId: "msg-legacy-1")
        guard message != nil && message?.content == "Hello from v1" else {
            print("  [FAIL] Existing message lost or corrupted")
            return false
        }
        
        database.close()
        print("  [PASS] SQLite v2/v3 migrations upgraded version to 3, backfilled operation_id, preserved all queued data")
        return true
    }
    
    // MARK: - 3. Installation Identity Manager & Lifecycle
    
    public func testInstallationIdentityLifecycle() -> Bool {
        print("\n[RUNNING] 3. Installation Identity Management & Backup Exclusion...")
        
        let testDir = URL(fileURLWithPath: "/tmp/offgrid_identity_test_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        let identityManager = InstallationIdentityManager(customStorageDirectory: testDir)
        let nodeId = identityManager.getNodeId()
        
        // Verify lowercase UUIDv4 format
        let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        guard nodeId.range(of: uuidPattern, options: String.CompareOptions.regularExpression) != nil else {
            print("  [FAIL] Node ID is not a valid lowercase UUIDv4: \(nodeId)")
            return false
        }
        
        // Verify marker file exists
        let markerUrl = identityManager.getMarkerFileURL()
        guard FileManager.default.fileExists(atPath: markerUrl.path) else {
            print("  [FAIL] Marker file does not exist at \(markerUrl.path)")
            return false
        }
        
        // Verify isExcludedFromBackup resource value
        guard let resourceValues = try? markerUrl.resourceValues(forKeys: [URLResourceKey.isExcludedFromBackupKey]),
              resourceValues.isExcludedFromBackup == true else {
            print("  [FAIL] Marker file is not marked isExcludedFromBackup = true")
            return false
        }
        
        // Verify repeatable node ID read
        let repeatedNodeId = identityManager.getNodeId()
        guard repeatedNodeId == nodeId else {
            print("  [FAIL] Consecutive getNodeId() calls returned different IDs")
            return false
        }
        
        print("  [PASS] Installation identity verified: lowercase UUIDv4 '\(nodeId)', backup-excluded marker present")
        return true
    }
    
    // MARK: - 4. Operation ID Uniqueness, Idempotency & Conflict Rejection
    
    public func testOperationIdUniquenessBehavior() -> Bool {
        print("\n[RUNNING] 4. Operation ID Uniqueness, Idempotency & Conflict Rejection...")
        
        let testDbPath = "/tmp/offgrid_unique_test_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
        }
        
        let database = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        
        let op1 = OFFGRIDOperation(
            id: "OP-UNIQUE-001",
            entityType: .message,
            entityId: "MSG-001",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"text\":\"Hello\"}"
        )
        
        // 1. New operation insert -> .inserted
        guard let res1 = try? database.insertOperation(op1), res1 == .inserted else {
            print("  [FAIL] Initial insert failed")
            return false
        }
        
        // 2. Exact duplicate with identical payload -> .duplicateIdentical (idempotent no-op)
        let opExactDup = OFFGRIDOperation(
            id: "OP-UNIQUE-001",
            entityType: .message,
            entityId: "MSG-001",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"text\":\"Hello\"}"
        )
        guard let res2 = try? database.insertOperation(opExactDup), res2 == .duplicateIdentical else {
            print("  [FAIL] Exact duplicate insert did not return .duplicateIdentical")
            return false
        }
        
        // 3. Case variant ID ("op-unique-001") with identical payload -> .duplicateIdentical
        let opCaseVariant = OFFGRIDOperation(
            id: "op-unique-001",
            entityType: .message,
            entityId: "MSG-001",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"text\":\"Hello\"}"
        )
        guard let res3 = try? database.insertOperation(opCaseVariant), res3 == .duplicateIdentical else {
            print("  [FAIL] Case-variant duplicate insert did not return .duplicateIdentical")
            return false
        }
        
        // 4. Same operation ID with DIFFERENT payload -> MUST THROW OperationStorageError.conflictingPayload!
        let opConflicting = OFFGRIDOperation(
            id: "OP-UNIQUE-001",
            entityType: .message,
            entityId: "MSG-001",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"text\":\"CONFLICTING PAYLOAD\"}"
        )
        var conflictRejected = false
        do {
            _ = try database.insertOperation(opConflicting)
        } catch let err as SQLiteDatabase.OperationStorageError {
            switch err {
            case .conflictingPayload(let opId, let existing, let new):
                if opId == "OP-UNIQUE-001" && existing == "{\"text\":\"Hello\"}" && new == "{\"text\":\"CONFLICTING PAYLOAD\"}" {
                    conflictRejected = true
                }
            default:
                break
            }
        } catch {
            print("  [FAIL] Unexpected error thrown: \(error)")
        }
        guard conflictRejected else {
            print("  [FAIL] Conflicting payload under existing operation ID was NOT rejected with explicit error!")
            return false
        }
        
        // 5. Different operation IDs with identical payload -> .inserted (both valid)
        let opDifferentId = OFFGRIDOperation(
            id: "OP-UNIQUE-002",
            entityType: .message,
            entityId: "MSG-002",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"text\":\"Hello\"}"
        )
        guard let res5 = try? database.insertOperation(opDifferentId), res5 == .inserted else {
            print("  [FAIL] Different operation ID with identical payload failed to insert")
            return false
        }
        
        let pending = database.fetchPendingOperations()
        guard pending.count == 2 else {
            print("  [FAIL] Expected exactly 2 operations in database, got \(pending.count)")
            return false
        }
        
        database.close()
        print("  [PASS] Uniqueness behavior verified: identical duplicates are idempotent, conflicting payloads explicitly rejected, distinct IDs with same payload accepted")
        return true
    }
    
    // MARK: - 5. Legacy Collision Aborts Migration Safely (Zero Data Loss)
    
    public func testLegacyCollisionAbortsMigrationSafely() -> Bool {
        print("\n[RUNNING] 5. Legacy Collision Aborts Migration Safely (Zero Data Loss)...")
        
        let testDbPath = "/tmp/offgrid_collision_abort_test_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
        }
        
        // Seed v1 database with two colliding rows under case-insensitivity
        var rawDb: OpaquePointer?
        sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        let seedSql = """
        PRAGMA user_version = 1;
        CREATE TABLE operations (id TEXT PRIMARY KEY, entity_type TEXT, entity_id TEXT, action TEXT, origin_node_id TEXT, timestamp REAL, lamport_clock INTEGER, payload_json TEXT, sync_status TEXT, retry_count INTEGER);
        INSERT INTO operations VALUES ('COLLIDE-1', 'MESSAGE', 'MSG-1', 'CREATE', 'NODE-1', 1700000000.0, 1, '{\"v\":1}', 'QUEUED', 0);
        INSERT INTO operations VALUES ('collide-1', 'MESSAGE', 'MSG-1', 'CREATE', 'NODE-1', 1700000001.0, 2, '{\"v\":2}', 'QUEUED', 1);
        """
        sqlite3_exec(rawDb, seedSql, nil, nil, nil)
        sqlite3_close_v2(rawDb)
        
        // Opening via SQLiteDatabase will attempt runMigrations() -> applyMigrationV2()
        // It must detect the collision, abort migration, and rollback without deleting anything
        let database = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        
        // Verify user_version remains 1
        var version = -1
        sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READONLY, nil)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(rawDb, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        // Verify both colliding rows are completely preserved (0 deleted!)
        var rowCount = 0
        if sqlite3_prepare_v2(rawDb, "SELECT COUNT(*) FROM operations;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                rowCount = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        sqlite3_close_v2(rawDb)
        database.close()
        
        guard version == 1 else {
            print("  [FAIL] user_version should have remained 1 on collision abort, got \(version)")
            return false
        }
        guard rowCount == 2 else {
            print("  [FAIL] Expected 2 rows preserved in database, got \(rowCount)")
            return false
        }
        
        print("  [PASS] Legacy collision detected: migration aborted safely, user_version remained 1, all 2 colliding records preserved intact")
        return true
    }
    
    // MARK: - 6. Fault-Injected Migration Atomicity & Rollback Verification
    
    public func testFaultInjectedMigrationAtomicityRollback() -> Bool {
        print("\n[RUNNING] 6. Fault-Injected Migration Atomicity & Rollback Verification...")
        
        let testDbPath = "/tmp/offgrid_fault_inject_test_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
            SQLiteDatabase.migrationV2FaultInjection = nil
        }
        
        // Seed populated v1 database
        var rawDb: OpaquePointer?
        sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        let seedSql = """
        PRAGMA user_version = 1;
        CREATE TABLE messages (id TEXT PRIMARY KEY, sender_id TEXT, sender_name TEXT, recipient_id TEXT, content TEXT, type TEXT, timestamp REAL, status TEXT, hop_count INTEGER, lamport_clock INTEGER);
        CREATE TABLE operations (id TEXT PRIMARY KEY, entity_type TEXT, entity_id TEXT, action TEXT, origin_node_id TEXT, timestamp REAL, lamport_clock INTEGER, payload_json TEXT, sync_status TEXT, retry_count INTEGER);
        INSERT INTO messages VALUES ('MSG-FAULT-1', 'NODE-1', 'Alice', 'NODE-2', 'Pre-migration message', 'chat', 1700000000.0, 'DELIVERED', 0, 1);
        INSERT INTO operations VALUES ('OP-FAULT-1', 'MESSAGE', 'MSG-FAULT-1', 'CREATE', 'NODE-1', 1700000000.0, 1, '{\"text\":\"Pre-migration\"}', 'QUEUED', 0);
        """
        sqlite3_exec(rawDb, seedSql, nil, nil, nil)
        sqlite3_close_v2(rawDb)
        
        // Activate fault injection hook to fail DURING applyMigrationV2 execution
        // (after columns have been added, before commit)
        SQLiteDatabase.migrationV2FaultInjection = {
            throw NSError(domain: "org.offgrid.test", code: 999, userInfo: [NSLocalizedDescriptionKey: "Simulated mid-migration system crash/power loss"])
        }
        
        // First open: Migration runs, adds column, triggers fault, catches, rolls back
        let failedDb = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        failedDb.close()
        
        // Verify database state after rollback
        sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READONLY, nil)
        var stmt: OpaquePointer?
        var versionAfterRollback = 0
        if sqlite3_prepare_v2(rawDb, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                versionAfterRollback = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        var colsAfterRollback: [String] = []
        if sqlite3_prepare_v2(rawDb, "PRAGMA table_info(operations);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 1) {
                    colsAfterRollback.append(String(cString: cName))
                }
            }
        }
        sqlite3_finalize(stmt)
        sqlite3_close_v2(rawDb)
        
        guard versionAfterRollback == 1 else {
            print("  [FAIL] user_version after fault rollback should be 1, got \(versionAfterRollback)")
            return false
        }
        guard !colsAfterRollback.contains("operation_id") && !colsAfterRollback.contains("base_version") else {
            print("  [FAIL] Columns were partially retained after rollback: \(colsAfterRollback)")
            return false
        }
        
        // Deactivate fault injection and re-open
        SQLiteDatabase.migrationV2FaultInjection = nil
        let recoveredDb = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        
        let migratedOp = recoveredDb.getOperation(byId: "OP-FAULT-1")
        let migratedMsg = recoveredDb.getMessage(byId: "MSG-FAULT-1")
        
        guard migratedOp != nil && migratedOp?.id == "OP-FAULT-1" else {
            print("  [FAIL] Operation lost after successful recovery")
            return false
        }
        guard migratedMsg != nil && migratedMsg?.content == "Pre-migration message" else {
            print("  [FAIL] Message lost after successful recovery")
            return false
        }
        guard recoveredDb.tableHasColumn(table: "operations", column: "operation_id") else {
            print("  [FAIL] Schema was not upgraded after recovery")
            return false
        }
        
        recoveredDb.close()
        print("  [PASS] Fault-injected migration atomicity verified: mid-migration failure cleanly rolled back to v1; subsequent restart completed v2 upgrade with zero data loss")
        return true
    }
    
    // MARK: - 7. Legacy Uppercase UUID Verbatim Preservation
    
    public func testLegacyUppercasePreservation() -> Bool {
        print("\n[RUNNING] 7. Legacy Uppercase UUID Verbatim Preservation...")
        
        let testDbPath = "/tmp/offgrid_legacy_uuid_test_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
        }
        
        let legacyNodeId = "82E52F6B-00CE-4967-93BF-4E6830AF9F73"
        let legacyMsgId = "A1B2C3D4-E5F6-4795-AC44-1A2068033C14"
        let legacyOpId = "D2CD0609-EADB-464C-B253-BD2F3926EBA4"
        
        // Seed v1 database with actual prototype uppercase UUIDs
        var rawDb: OpaquePointer?
        sqlite3_open_v2(testDbPath, &rawDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        let createV1 = """
        PRAGMA user_version = 1;
        CREATE TABLE messages (
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
        CREATE TABLE operations (
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
        INSERT INTO messages VALUES ('\(legacyMsgId)', '\(legacyNodeId)', 'Me', '*', 'SOS Beacon', 'sos', 1700000000.0, 'LOCAL_ONLY', 0, 1);
        INSERT INTO operations VALUES ('\(legacyOpId)', 'SOS', '\(legacyMsgId)', 'CREATE', '\(legacyNodeId)', 1700000000.0, 1, '{\"text\":\"Emergency\"}', 'QUEUED', 2);
        """
        sqlite3_exec(rawDb, createV1, nil, nil, nil)
        sqlite3_close_v2(rawDb)
        
        // Open with SQLiteDatabase to trigger v2 migration
        let database = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        
        // Verify that existing records retain their exact original uppercase IDs
        let op = database.getOperation(byId: legacyOpId)
        guard let retrievedOp = op else {
            print("  [FAIL] Legacy operation not found by original ID")
            return false
        }
        
        guard retrievedOp.id == legacyOpId,
              retrievedOp.entityId == legacyMsgId,
              retrievedOp.originNodeId == legacyNodeId,
              retrievedOp.retryCount == 2 else {
            print("  [FAIL] Legacy operation fields were altered or lowercased during migration!")
            return false
        }
        
        let msg = database.getMessage(byId: legacyMsgId)
        guard let retrievedMsg = msg, retrievedMsg.senderId == legacyNodeId else {
            print("  [FAIL] Legacy message fields were altered during migration!")
            return false
        }
        
        // Verify case-insensitive operation query
        let opByLower = database.getOperation(byOperationId: legacyOpId.lowercased())
        guard opByLower?.id == legacyOpId else {
            print("  [FAIL] Operation lookup by lowercased ID failed to match legacy uppercase record")
            return false
        }
        
        database.close()
        print("  [PASS] Legacy uppercase UUIDs preserved byte-for-byte; retry identity and case-insensitive lookups intact")
        return true
    }
}
