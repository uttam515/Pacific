import Foundation
import SQLite3

public final class SQLitePersistenceTests {
    private let testDbPath: String

    public init() {
        self.testDbPath = "/tmp/offgrid_restart_test_\(UUID().uuidString).sqlite"
    }

    public func cleanUp() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: testDbPath)
        try? fileManager.removeItem(atPath: testDbPath + "-wal")
        try? fileManager.removeItem(atPath: testDbPath + "-shm")
    }

    public func runAllTests() -> Bool {
        print("\n===========================================")
        print("  OFFGRID iOS SQLite Persistence Test Suite")
        print("===========================================")

        var passed = true
        passed = runTest("1. Message creation without internet & local SQLite save", testMessageCreationAndPersistence) && passed
        passed = runTest("2. Simulate termination, reopen, and verify persistence", testApplicationTerminationAndReopen) && passed
        passed = runTest("3. Atomic message & operation transaction integrity", testAtomicTransaction) && passed
        passed = runTest("4. Duplicate operation suppression & idempotency", testDuplicateOperationSuppression) && passed
        passed = runTest("5. Message & operation status lifecycle transitions", testStatusTransitions) && passed

        cleanUp()

        print("===========================================")
        if passed {
            print("  ALL SQLITE PERSISTENCE TESTS PASSED!")
        } else {
            print("  SOME TESTS FAILED!")
        }
        print("===========================================\n")
        return passed
    }

    private func runTest(_ name: String, _ testBlock: () throws -> Void) -> Bool {
        print("\n[RUNNING] \(name)...")
        do {
            try testBlock()
            print("[PASS] \(name)")
            return true
        } catch {
            print("[FAIL] \(name): \(error)")
            return false
        }
    }

    // Test 1: Message created without internet and saved in SQLite
    public func testMessageCreationAndPersistence() throws {
        let db = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let messageId = UUID().uuidString
        let opId = UUID().uuidString
        let message = OFFGRIDMessage(
            id: messageId,
            senderId: "NODE-TEST-001",
            senderName: "Tester",
            recipientId: "*",
            content: "Hello offline world",
            type: .chat,
            timestamp: Date(),
            status: .localOnly
        )

        let op = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: messageId,
            action: .create,
            originNodeId: "NODE-TEST-001",
            timestamp: Date(),
            lamportClock: 1,
            payloadJson: "{\"content\":\"Hello offline world\"}",
            syncStatus: .localOnly
        )

        // Atomically save
        try repo.saveMessageWithOperation(message: message, operation: op)

        // Verify message saved
        guard let fetchedMessage = repo.getMessage(id: messageId) else {
            throw TestError.assertionFailed("Message not found after save")
        }
        guard fetchedMessage.content == "Hello offline world" else {
            throw TestError.assertionFailed("Message content mismatch")
        }
        guard fetchedMessage.status == .localOnly else {
            throw TestError.assertionFailed("Initial status must be localOnly")
        }

        // Verify operation queued
        guard let fetchedOp = opRepo.getOperation(id: opId) else {
            throw TestError.assertionFailed("Operation not found in queue")
        }
        guard fetchedOp.id == opId else {
            throw TestError.assertionFailed("Operation ID mismatch")
        }
        guard fetchedOp.syncStatus == .localOnly else {
            throw TestError.assertionFailed("Operation sync status must be localOnly")
        }
    }

    // Test 2: Simulate App Termination, Reopen, and Verify
    public func testApplicationTerminationAndReopen() throws {
        let messageId = "RESTART-MSG-" + UUID().uuidString
        let opId = "RESTART-OP-" + UUID().uuidString

        // Phase A: Write before termination
        do {
            let db = SQLiteDatabase(inMemory: false, customPath: testDbPath)
            let repo = MessageRepository(database: db)

            let msg = OFFGRIDMessage(
                id: messageId,
                senderId: "NODE-TERMINATION-TEST",
                senderName: "Surviving Node",
                recipientId: "*",
                content: "Crucial alert surviving process death",
                type: .chat,
                timestamp: Date(),
                status: .queued
            )

            let op = OFFGRIDOperation(
                id: opId,
                entityType: .message,
                entityId: messageId,
                action: .create,
                originNodeId: "NODE-TERMINATION-TEST",
                timestamp: Date(),
                lamportClock: 42,
                payloadJson: "{}",
                syncStatus: .queued
            )

            try repo.saveMessageWithOperation(message: msg, operation: op)
            // Simulate process termination by explicitly closing database pointer
            db.close()
            print("  -> Application terminated (SQLite connection closed, WAL flushed).")
        }

        // Phase B: Simulate App Launch after termination
        do {
            print("  -> Application restarted (Instantiating new database handle from disk).")
            let dbNew = SQLiteDatabase(inMemory: false, customPath: testDbPath)
            let repoNew = MessageRepository(database: dbNew)
            let opRepoNew = OperationQueueRepository(database: dbNew)

            // 1. Verify message is still present
            guard let recoveredMessage = repoNew.getMessage(id: messageId) else {
                throw TestError.assertionFailed("Recovered message missing after restart!")
            }
            guard recoveredMessage.content == "Crucial alert surviving process death" else {
                throw TestError.assertionFailed("Recovered message content corrupted!")
            }

            // 2. Verify pending operation is still available
            let pendingOps = opRepoNew.getPendingOperations()
            guard let recoveredOp = pendingOps.first(where: { $0.id == opId }) else {
                throw TestError.assertionFailed("Pending operation missing from queue after restart!")
            }

            // 3. Verify operation ID remains unchanged
            guard recoveredOp.id == opId else {
                throw TestError.assertionFailed("Operation ID changed after restart! Expected \(opId), got \(recoveredOp.id)")
            }
            guard recoveredOp.entityId == messageId else {
                throw TestError.assertionFailed("Entity ID mismatch after restart!")
            }
            guard recoveredOp.lamportClock == 42 else {
                throw TestError.assertionFailed("Lamport clock corrupted after restart!")
            }
            print("  -> Recovered message and pending operation intact with unchanged IDs.")
        }
    }

    // Test 3: Atomic Transaction Rollback
    public func testAtomicTransaction() throws {
        let db = SQLiteDatabase(inMemory: false, customPath: testDbPath)

        let initialCount = db.fetchMessages().count

        // Attempt a transaction that throws halfway
        do {
            try db.performTransaction {
                let msg = OFFGRIDMessage(
                    id: "TRANSACTION-FAIL-MSG",
                    senderId: "FAIL-TEST",
                    senderName: "Tester",
                    content: "Should not be committed",
                    type: .chat
                )
                db.insertMessage(msg)
                throw TestError.simulatedFailure
            }
        } catch TestError.simulatedFailure {
            // Expected
        }

        let afterCount = db.fetchMessages().count
        guard initialCount == afterCount else {
            throw TestError.assertionFailed("Transaction failed to roll back! Uncommitted message was saved.")
        }
        guard db.getMessage(byId: "TRANSACTION-FAIL-MSG") == nil else {
            throw TestError.assertionFailed("Uncommitted message found in database!")
        }
    }

    // Test 4: Duplicate Operation Suppression
    public func testDuplicateOperationSuppression() throws {
        let db = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        let opRepo = OperationQueueRepository(database: db)

        let opId = "IDEMPOTENT-OP-" + UUID().uuidString
        let op1 = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: "MSG-1",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"v\":1}",
            syncStatus: .localOnly,
            retryCount: 0
        )

        opRepo.enqueue(operation: op1)
        opRepo.markStatus(operationId: opId, status: .peerRelayed)
        opRepo.incrementRetry(operationId: opId)

        // Try inserting same operation again with different sync status
        let opDuplicate = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: "MSG-1",
            action: .create,
            originNodeId: "NODE-1",
            payloadJson: "{\"v\":1}",
            syncStatus: .localOnly,
            retryCount: 0
        )
        opRepo.enqueue(operation: opDuplicate)

        // Existing state must NOT be wiped or reset
        guard let savedOp = opRepo.getOperation(id: opId) else {
            throw TestError.assertionFailed("Operation missing")
        }
        guard savedOp.syncStatus == .peerRelayed else {
            throw TestError.assertionFailed("Duplicate insert reset status from peerRelayed to \(savedOp.syncStatus)")
        }
        guard savedOp.retryCount == 1 else {
            throw TestError.assertionFailed("Duplicate insert wiped retry count")
        }
    }

    // Test 5: Status Transitions
    public func testStatusTransitions() throws {
        let db = SQLiteDatabase(inMemory: false, customPath: testDbPath)
        let msgRepo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let msgId = "LIFECYCLE-MSG-" + UUID().uuidString
        let opId = "LIFECYCLE-OP-" + UUID().uuidString

        let msg = OFFGRIDMessage(id: msgId, senderId: "NODE-1", senderName: "Node1", content: "Lifecycle Test", status: .localOnly)
        let op = OFFGRIDOperation(id: opId, entityType: .message, entityId: msgId, action: .create, originNodeId: "NODE-1", payloadJson: "{}", syncStatus: .localOnly)

        try msgRepo.saveMessageWithOperation(message: msg, operation: op)

        // localOnly -> queued
        msgRepo.updateStatus(id: msgId, status: .queued)
        opRepo.markStatus(operationId: opId, status: .queued)
        guard msgRepo.getMessage(id: msgId)?.status == .queued else { throw TestError.assertionFailed("Failed to update to queued") }

        // queued -> relayed
        msgRepo.updateStatus(id: msgId, status: .relayed)
        opRepo.markStatus(operationId: opId, status: .peerRelayed)
        guard msgRepo.getMessage(id: msgId)?.status == .relayed else { throw TestError.assertionFailed("Failed to update to relayed") }

        // relayed -> delivered (peer ACK)
        msgRepo.updateStatus(id: msgId, status: .delivered)
        guard msgRepo.getMessage(id: msgId)?.status == .delivered else { throw TestError.assertionFailed("Failed to update to delivered") }

        // delivered -> synced (gateway ACK)
        msgRepo.updateStatus(id: msgId, status: .synced)
        opRepo.markStatus(operationId: opId, status: .gatewaySynced)
        guard msgRepo.getMessage(id: msgId)?.status == .synced else { throw TestError.assertionFailed("Failed to update to synced") }

        // Gateway synced operation should no longer be in pending list
        let pending = opRepo.getPendingOperations()
        guard !pending.contains(where: { $0.id == opId }) else {
            throw TestError.assertionFailed("Synced operation still in pending list")
        }
    }

    public enum TestError: Error {
        case assertionFailed(String)
        case simulatedFailure
    }
}
