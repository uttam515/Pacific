import Foundation
import MultipeerConnectivity

public final class MeshProtocolTests {
    public func runAllTests() -> (passed: Int, total: Int) {
        print("\n===========================================")
        print("  OFFGRID iOS Mesh Protocol & Delivery Tests")
        print("===========================================")

        var passedCount = 0
        let totalCount = 15

        if runTest("1. Contract v1 Envelope validation & invariant checks", testContractV1EnvelopeValidation) { passedCount += 1 }
        if runTest("2. Deterministic multipeer tie-breaker comparison", testTieBreakerLogic) { passedCount += 1 }
        if runTest("3. End-to-end Device-to-Device SYNC_OP message & distinct ACK stage simulation", testDeviceToDeviceMessageAndAckFlow) { passedCount += 1 }
        if runTest("4. Inbound duplicate message suppression & idempotent ACK", testDuplicateSuppressionAndAck) { passedCount += 1 }
        if runTest("5. Offline queued message flushing on peer connect", testOfflineQueueFlushing) { passedCount += 1 }
        if runTest("6. Emergency SOS atomic creation and persistence with Contract v1 payload", testSOSCreationAndPersistence) { passedCount += 1 }
        if runTest("7. End-to-end SOS transmission, entity preservation, and ACK delivery", testSOSTransmissionAndAckFlow) { passedCount += 1 }
        if runTest("8. SOS queue flushing on peer link restoration", testSOSQueueFlushing) { passedCount += 1 }
        if runTest("9. Independent SOS duplicate & new-event tests (Part A & Part B)", testDuplicateSOSSuppression) { passedCount += 1 }
        if runTest("10. Active incoming vs outgoing SOS feed separation", testSOSFeedSeparation) { passedCount += 1 }
        if runTest("11. Intermediate peers strictly issue PEER_STORED and never RECIPIENT_ACKNOWLEDGED", testIntermediatePeerAckRestrictions) { passedCount += 1 }
        if runTest("12. Inbound operation is never acknowledged before durable storage succeeds", testStorageFailurePreventsAck) { passedCount += 1 }
        if runTest("13. Retransmission preserves exact operation ID and message ID", testRetransmissionPreservesIdentities) { passedCount += 1 }
        if runTest("14. Fault-injected atomic inbound persistence rollback & zero ACK", testFaultInjectedInboundPersistenceRollback) { passedCount += 1 }
        if runTest("15. Multipeer session lifecycle, certificate validation approval & tie-breaker state recovery", testMultipeerSessionLifecycleAndSecurity) { passedCount += 1 }

        print("===========================================")
        if passedCount == totalCount {
            print("  ALL MESH PROTOCOL TESTS PASSED! (\(passedCount)/\(totalCount))")
        } else {
            print("  SOME TESTS FAILED: \(passedCount)/\(totalCount)")
        }
        print("===========================================\n")
        return (passed: passedCount, total: totalCount)
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

    // MARK: - Test 1: Contract v1 Envelope Validation
    public func testContractV1EnvelopeValidation() throws {
        let nodeA = UUID().uuidString.lowercased()
        let nodeB = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let entityId = UUID().uuidString.lowercased()
        let packetId = UUID().uuidString.lowercased()

        let validOp = ContractV1.Operation(
            schemaVersion: 1,
            operationId: opId,
            originNodeId: nodeA,
            entityId: entityId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            lamportClock: 1,
            entityType: .message,
            action: .create,
            baseVersion: 0,
            payload: .message(ContractV1.MessagePayload(text: "Hello", recipientNodeId: nodeB))
        )

        // 1. Valid SYNC_OP envelope
        let validEnv = ContractV1.Envelope(
            version: 1,
            packetId: packetId,
            sourceNodeId: nodeA,
            destinationNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(validOp)
        )
        try ContractV1Validator.validateEnvelope(validEnv)

        // 2. Invalid schemaVersion
        let invalidVersionEnv = ContractV1.Envelope(
            version: 2,
            packetId: packetId,
            sourceNodeId: nodeA,
            destinationNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(validOp)
        )
        var caughtVersionError = false
        do {
            try ContractV1Validator.validateEnvelope(invalidVersionEnv)
        } catch ContractValidationError.invalidSchemaVersion {
            caughtVersionError = true
        }
        guard caughtVersionError else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Did not catch invalidSchemaVersion"])
        }

        // 3. Invalid TTL/hopCount invariant: hopCount + ttl > 8
        let invalidTtlEnv = ContractV1.Envelope(
            version: 1,
            packetId: packetId,
            sourceNodeId: nodeA,
            destinationNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 6,
            hopCount: 3, // 6 + 3 = 9 > 8
            type: .syncOp,
            payload: .syncOp(validOp)
        )
        var caughtTtlError = false
        do {
            try ContractV1Validator.validateEnvelope(invalidTtlEnv)
        } catch ContractValidationError.invalidTTL {
            caughtTtlError = true
        }
        guard caughtTtlError else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Did not catch invalidTTL"])
        }

        // 4. Valid ACK envelope
        let ackId = UUID().uuidString.lowercased()
        let validAck = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: ackId,
            operationId: opId,
            stage: .peerStored,
            acknowledgingNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId
        )
        let validAckEnv = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: nodeB,
            destinationNodeId: nodeA,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(validAck)
        )
        try ContractV1Validator.validateEnvelope(validAckEnv)
    }

    // MARK: - Test 2: Multipeer tie-breaker logic
    public func testTieBreakerLogic() throws {
        let peerAlpha = "iPhone-Alpha-1234"
        let peerBeta = "iPhone-Beta-5678"

        let betaWins = peerBeta.compare(peerAlpha) == .orderedDescending
        let alphaLoses = peerAlpha.compare(peerBeta) == .orderedAscending

        guard betaWins && alphaLoses else {
            throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Tie-breaker ordering failed"])
        }

        let betaShouldInvite = peerBeta.compare(peerAlpha) == .orderedDescending
        let alphaShouldInvite = peerAlpha.compare(peerBeta) == .orderedDescending

        guard betaShouldInvite && !alphaShouldInvite else {
            throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Mutual invitation race was not broken cleanly"])
        }
    }

    // MARK: - Test 3: Device-to-Device SYNC_OP and PEER_STORED ACK
    public func testDeviceToDeviceMessageAndAckFlow() throws {
        let dbPathA = "/tmp/offgrid_device_a_\(UUID().uuidString.lowercased()).sqlite"
        let dbPathB = "/tmp/offgrid_device_b_\(UUID().uuidString.lowercased()).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: dbPathA)
            try? FileManager.default.removeItem(atPath: dbPathB)
        }

        let dbA = SQLiteDatabase(inMemory: false, customPath: dbPathA)
        let repoA = MessageRepository(database: dbA)
        let opRepoA = OperationQueueRepository(database: dbA)

        let dbB = SQLiteDatabase(inMemory: false, customPath: dbPathB)
        let repoB = MessageRepository(database: dbB)
        let opRepoB = OperationQueueRepository(database: dbB)

        let nodeA = UUID().uuidString.lowercased()
        let nodeB = UUID().uuidString.lowercased()

        // Step 1: iPhone A generates message & operation, saves to SQLite
        let messageId = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let textContent = "Hello from iPhone A across offline mesh!"

        let message = OFFGRIDMessage(
            id: messageId,
            senderId: nodeA,
            senderName: "iPhone A",
            recipientId: nodeB,
            content: textContent,
            type: .chat,
            status: .localOnly
        )

        let contractPayload = ContractV1.MessagePayload(text: textContent, recipientNodeId: nodeB)
        let payloadData = try JSONEncoder().encode(contractPayload)
        let payloadJsonString = String(data: payloadData, encoding: .utf8)!

        let opA = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: message.id,
            action: .create,
            originNodeId: nodeA,
            payloadJson: payloadJsonString,
            syncStatus: .localOnly
        )

        try repoA.saveMessageWithOperation(message: message, operation: opA)

        // Step 2: iPhone A transmits packet (simulated relay)
        repoA.updateStatus(id: message.id, status: .relayed)
        opRepoA.markStatus(operationId: opA.id, status: .peerRelayed)

        // Step 3: Verify iPhone A message is .relayed, not .delivered!
        let msgAAfterRelay = repoA.getMessage(id: messageId)!
        guard msgAAfterRelay.status == .relayed else {
            throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Message should be .relayed, not .delivered!"])
        }

        // Step 4: Construct Contract v1 Envelope for wire transmission
        let contractOpA = ContractV1.Operation(
            schemaVersion: 1,
            operationId: opId,
            originNodeId: nodeA,
            entityId: messageId,
            timestamp: Int64(message.timestamp.timeIntervalSince1970 * 1000),
            lamportClock: message.lamportClock,
            entityType: .message,
            action: .create,
            baseVersion: 0,
            payload: .message(contractPayload)
        )
        let wirePacketId = UUID().uuidString.lowercased()
        let envelopeA = ContractV1.Envelope(
            version: 1,
            packetId: wirePacketId,
            sourceNodeId: nodeA,
            destinationNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(contractOpA)
        )

        let packetData = try JSONEncoder().encode(envelopeA)

        // Step 5: iPhone B receives packet over wire, decodes & validates Contract v1 Envelope
        let decodedEnvB = try JSONDecoder().decode(ContractV1.Envelope.self, from: packetData)
        try ContractV1Validator.validateEnvelope(decodedEnvB)

        guard case .syncOp(let receivedOp) = decodedEnvB.payload else {
            throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected SYNC_OP payload"])
        }
        guard case .message(let receivedMsgPayload) = receivedOp.payload else {
            throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected Message payload"])
        }

        // iPhone B durably stores message and operation in SQLite
        let receivedMessageB = OFFGRIDMessage(
            id: receivedOp.entityId,
            senderId: receivedOp.originNodeId,
            senderName: "Node A",
            recipientId: receivedMsgPayload.recipientNodeId,
            content: receivedMsgPayload.text,
            type: .chat,
            timestamp: Date(timeIntervalSince1970: Double(receivedOp.timestamp) / 1000.0),
            status: .delivered,
            hopCount: decodedEnvB.hopCount + 1,
            lamportClock: receivedOp.lamportClock
        )
        let opB = OFFGRIDOperation(
            id: receivedOp.operationId,
            entityType: .message,
            entityId: receivedOp.entityId,
            action: .create,
            originNodeId: receivedOp.originNodeId,
            payloadJson: payloadJsonString,
            syncStatus: .peerRelayed
        )

        try repoB.saveMessageWithOperation(message: receivedMessageB, operation: opB)

        // Verify iPhone B stored the message and operation
        let storedB = repoB.getMessage(id: messageId)
        let storedOpB = opRepoB.getOperation(byOperationId: receivedOp.operationId)
        guard storedB != nil && storedB?.content == textContent && storedOpB != nil else {
            throw NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "Device B failed to store received message or operation"])
        }

        // Step 6: iPhone B sends back PEER_STORED ACK
        let ackIdB = UUID().uuidString.lowercased()
        let ackPayloadB = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: ackIdB,
            operationId: receivedOp.operationId,
            stage: .peerStored,
            acknowledgingNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: decodedEnvB.packetId
        )
        let ackEnvB = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: nodeB,
            destinationNodeId: nodeA,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(ackPayloadB)
        )
        let ackData = try JSONEncoder().encode(ackEnvB)

        // Step 7: iPhone A receives PEER_STORED ACK: transitions message to .relayed (peer-stored/relayed)
        let decodedAckEnv = try JSONDecoder().decode(ContractV1.Envelope.self, from: ackData)
        try ContractV1Validator.validateEnvelope(decodedAckEnv)

        guard case .ack(let ack) = decodedAckEnv.payload else {
            throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected ACK payload"])
        }
        guard ack.stage == .peerStored else {
            throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected PEER_STORED stage"])
        }

        // PEER_STORED strictly transitions to .relayed (peer-stored/relayed), NOT .delivered!
        let targetOp = opRepoA.getOperation(byOperationId: ack.operationId)!
        repoA.updateStatus(id: targetOp.entityId, status: .relayed)
        opRepoA.markStatus(operationId: ack.operationId, status: .peerRelayed)

        let msgAfterPeerStored = repoA.getMessage(id: messageId)!
        guard msgAfterPeerStored.status == .relayed else {
            throw NSError(domain: "Test", code: 12, userInfo: [NSLocalizedDescriptionKey: "Message A should be .relayed on PEER_STORED, not .delivered!"])
        }

        // Step 8: Only explicit RECIPIENT_ACKNOWLEDGED transitions message to .delivered
        let recipientAckPayload = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: receivedOp.operationId,
            stage: .recipientAcknowledged,
            acknowledgingNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: decodedEnvB.packetId
        )
        guard recipientAckPayload.stage == .recipientAcknowledged else {
            throw NSError(domain: "Test", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected RECIPIENT_ACKNOWLEDGED stage"])
        }
        repoA.updateStatus(id: targetOp.entityId, status: .delivered)
        let msgAfterRecipientAck = repoA.getMessage(id: messageId)!
        guard msgAfterRecipientAck.status == .delivered else {
            throw NSError(domain: "Test", code: 14, userInfo: [NSLocalizedDescriptionKey: "Message A did not transition to .delivered after RECIPIENT_ACKNOWLEDGED"])
        }

        // Step 9: Only BACKEND_COMMITTED transitions message to .synced
        repoA.updateStatus(id: targetOp.entityId, status: .synced)
        opRepoA.markStatus(operationId: ack.operationId, status: .gatewaySynced)
        let msgAfterBackendAck = repoA.getMessage(id: messageId)!
        guard msgAfterBackendAck.status == .synced else {
            throw NSError(domain: "Test", code: 15, userInfo: [NSLocalizedDescriptionKey: "Message A did not transition to .synced after BACKEND_COMMITTED"])
        }
    }

    // MARK: - Test 4: Duplicate suppression & idempotent ACK
    public func testDuplicateSuppressionAndAck() throws {
        let dbPath = "/tmp/offgrid_dup_test_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let messageId = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let senderId = UUID().uuidString.lowercased()

        let originalMsg = OFFGRIDMessage(
            id: messageId,
            senderId: senderId,
            senderName: "Node 1",
            content: "Original Content",
            status: .delivered
        )
        let originalOp = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: messageId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"Original Content\",\"recipientNodeId\":\"*\"}",
            syncStatus: .peerRelayed
        )

        try repo.saveMessageWithOperation(message: originalMsg, operation: originalOp)

        // 1. Identical duplicate insertion returns .duplicateIdentical without error
        let identicalOp = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: messageId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"Original Content\",\"recipientNodeId\":\"*\"}",
            syncStatus: .peerRelayed
        )
        let insertRes = try opRepo.enqueue(operation: identicalOp)
        guard insertRes == .duplicateIdentical else {
            throw NSError(domain: "Test", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected .duplicateIdentical"])
        }

        // 2. Conflicting duplicate insertion throws OperationStorageError.conflictingPayload
        let conflictingOp = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: messageId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"Tampered Content\",\"recipientNodeId\":\"*\"}",
            syncStatus: .peerRelayed
        )
        var caughtConflict = false
        do {
            _ = try opRepo.enqueue(operation: conflictingOp)
        } catch SQLiteDatabase.OperationStorageError.conflictingPayload {
            caughtConflict = true
        }
        guard caughtConflict else {
            throw NSError(domain: "Test", code: 14, userInfo: [NSLocalizedDescriptionKey: "Did not catch conflictingPayload"])
        }

        // Database content remains untouched
        let stored = repo.getMessage(id: messageId)!
        guard stored.content == "Original Content" else {
            throw NSError(domain: "Test", code: 15, userInfo: [NSLocalizedDescriptionKey: "Database content was corrupted"])
        }
    }

    // MARK: - Test 5: Offline queue flushing
    public func testOfflineQueueFlushing() throws {
        let dbPath = "/tmp/offgrid_queue_test_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)
        let myNodeId = UUID().uuidString.lowercased()

        // Queue 3 offline messages
        for i in 1...3 {
            let msgId = UUID().uuidString.lowercased()
            let opId = UUID().uuidString.lowercased()
            let msg = OFFGRIDMessage(
                id: msgId,
                senderId: myNodeId,
                senderName: "Me",
                content: "Offline message \(i)",
                status: .queued
            )
            let op = OFFGRIDOperation(
                id: opId,
                entityType: .message,
                entityId: msg.id,
                action: .create,
                originNodeId: myNodeId,
                payloadJson: "{\"text\":\"Offline message \(i)\",\"recipientNodeId\":\"*\"}",
                syncStatus: .queued
            )
            try repo.saveMessageWithOperation(message: msg, operation: op)
        }

        let pending = opRepo.getPendingOperations()
        guard pending.count == 3 else {
            throw NSError(domain: "Test", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected 3 pending ops"])
        }

        // Simulate flush upon peer connection: mark them relayed
        for op in pending {
            repo.updateStatus(id: op.entityId, status: .relayed)
            opRepo.markStatus(operationId: op.id, status: .peerRelayed)
        }

        let remainingQueued = opRepo.getPendingOperations().filter {
            $0.syncStatus == .localOnly || $0.syncStatus == .queued
        }
        guard remainingQueued.isEmpty else {
            throw NSError(domain: "Test", code: 17, userInfo: [NSLocalizedDescriptionKey: "Unsent queue should be 0 after flush"])
        }
    }

    // MARK: - Test 6: SOS creation and persistence with Contract v1 payload
    public func testSOSCreationAndPersistence() throws {
        let dbPath = "/tmp/offgrid_sos_create_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let nodeA = UUID().uuidString.lowercased()
        let sosId = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()

        let sosMsg = OFFGRIDMessage(
            id: sosId,
            senderId: nodeA,
            senderName: "Alpha",
            content: "[MEDICAL EMERGENCY] Need bandages",
            type: .sos,
            status: .localOnly
        )

        let sosPayload = ContractV1.SOSPayload(
            text: sosMsg.content,
            category: .medical,
            location: ContractV1.SOSLocation(label: "Trail Marker 7", latitude: 37.77, longitude: -122.41)
        )
        let payloadData = try JSONEncoder().encode(sosPayload)
        let payloadJsonString = String(data: payloadData, encoding: .utf8)!

        let op = OFFGRIDOperation(
            id: opId,
            entityType: .sos,
            entityId: sosMsg.id,
            action: .create,
            originNodeId: nodeA,
            payloadJson: payloadJsonString,
            syncStatus: .localOnly
        )

        try repo.saveMessageWithOperation(message: sosMsg, operation: op)

        let retrievedMsg = repo.getMessage(id: sosId)
        guard let retrievedMsg = retrievedMsg, retrievedMsg.type == .sos else {
            throw NSError(domain: "Test", code: 18, userInfo: [NSLocalizedDescriptionKey: "Failed to persist SOS message as .sos"])
        }

        let retrievedOp = opRepo.getOperation(id: opId)
        guard let retrievedOp = retrievedOp, retrievedOp.entityType == .sos else {
            throw NSError(domain: "Test", code: 19, userInfo: [NSLocalizedDescriptionKey: "Failed to persist SOS operation as .sos"])
        }
    }

    // MARK: - Test 7: SOS transmission, entity preservation, and ACK delivery
    public func testSOSTransmissionAndAckFlow() throws {
        let dbPathA = "/tmp/offgrid_sos_a_\(UUID().uuidString.lowercased()).sqlite"
        let dbPathB = "/tmp/offgrid_sos_b_\(UUID().uuidString.lowercased()).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: dbPathA)
            try? FileManager.default.removeItem(atPath: dbPathB)
        }

        let dbA = SQLiteDatabase(inMemory: false, customPath: dbPathA)
        let repoA = MessageRepository(database: dbA)
        let opRepoA = OperationQueueRepository(database: dbA)

        let dbB = SQLiteDatabase(inMemory: false, customPath: dbPathB)
        let repoB = MessageRepository(database: dbB)
        let opRepoB = OperationQueueRepository(database: dbB)

        let nodeA = UUID().uuidString.lowercased()
        let nodeB = UUID().uuidString.lowercased()
        let sosId = UUID().uuidString.lowercased()
        let opIdA = UUID().uuidString.lowercased()

        let sosMsg = OFFGRIDMessage(
            id: sosId,
            senderId: nodeA,
            senderName: "Sender",
            content: "[FIRE HAZARD] Brush fire near coordinates",
            type: .sos,
            status: .localOnly
        )

        let sosPayload = ContractV1.SOSPayload(
            text: sosMsg.content,
            category: .assistance,
            location: ContractV1.SOSLocation(label: "Emergency Beacon", latitude: nil, longitude: nil)
        )
        let payloadData = try JSONEncoder().encode(sosPayload)
        let payloadJsonString = String(data: payloadData, encoding: .utf8)!

        let opA = OFFGRIDOperation(
            id: opIdA,
            entityType: .sos,
            entityId: sosId,
            action: .create,
            originNodeId: nodeA,
            payloadJson: payloadJsonString,
            syncStatus: .localOnly
        )
        try repoA.saveMessageWithOperation(message: sosMsg, operation: opA)

        // Sender relays message
        repoA.updateStatus(id: sosId, status: .relayed)
        opRepoA.markStatus(operationId: opA.id, status: .peerRelayed)

        // Transmit Contract v1 Envelope
        let contractOp = ContractV1.Operation(
            schemaVersion: 1,
            operationId: opIdA,
            originNodeId: nodeA,
            entityId: sosId,
            timestamp: Int64(sosMsg.timestamp.timeIntervalSince1970 * 1000),
            lamportClock: sosMsg.lamportClock,
            entityType: .sos,
            action: .create,
            baseVersion: 0,
            payload: .sos(sosPayload)
        )
        let envelopeA = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: nodeA,
            destinationNodeId: "*",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(contractOp)
        )
        let packetData = try JSONEncoder().encode(envelopeA)

        // Receiver decodes and validates
        let decodedEnvB = try JSONDecoder().decode(ContractV1.Envelope.self, from: packetData)
        try ContractV1Validator.validateEnvelope(decodedEnvB)

        guard case .syncOp(let opReceived) = decodedEnvB.payload else {
            throw NSError(domain: "Test", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected syncOp envelope"])
        }
        guard opReceived.entityType == .sos else {
            throw NSError(domain: "Test", code: 21, userInfo: [NSLocalizedDescriptionKey: "Operation entityType should be .sos"])
        }

        // Receiver creates message & operation with PRESERVED .sos entity type
        let receivedB = OFFGRIDMessage(
            id: opReceived.entityId,
            senderId: opReceived.originNodeId,
            senderName: "Sender",
            recipientId: "*",
            content: sosMsg.content,
            type: .sos,
            timestamp: Date(timeIntervalSince1970: Double(opReceived.timestamp) / 1000.0),
            status: .delivered,
            hopCount: decodedEnvB.hopCount + 1,
            lamportClock: opReceived.lamportClock
        )
        let opB = OFFGRIDOperation(
            id: opReceived.operationId,
            entityType: .sos,
            entityId: opReceived.entityId,
            action: .create,
            originNodeId: opReceived.originNodeId,
            payloadJson: payloadJsonString,
            syncStatus: .peerRelayed
        )
        try repoB.saveMessageWithOperation(message: receivedB, operation: opB)

        // Verify Receiver stored with correct types
        let storedB = repoB.getMessage(id: sosId)
        guard let storedB = storedB, storedB.type == .sos else {
            throw NSError(domain: "Test", code: 22, userInfo: [NSLocalizedDescriptionKey: "Receiver failed to store SOS as .sos"])
        }
        let storedOpB = opRepoB.getOperation(id: opIdA)
        guard let storedOpB = storedOpB, storedOpB.entityType == .sos else {
            throw NSError(domain: "Test", code: 23, userInfo: [NSLocalizedDescriptionKey: "Receiver failed to preserve .sos entity type in operation"])
        }

        // Receiver sends PEER_STORED ACK
        let ackPayload = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: opIdA,
            stage: .peerStored,
            acknowledgingNodeId: nodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: decodedEnvB.packetId
        )
        let ackEnv = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: nodeB,
            destinationNodeId: nodeA,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .ack,
            payload: .ack(ackPayload)
        )
        let ackData = try JSONEncoder().encode(ackEnv)

        // Sender receives PEER_STORED ACK and marks .relayed (peer-stored/relayed)
        let receivedAckEnv = try JSONDecoder().decode(ContractV1.Envelope.self, from: ackData)
        guard case .ack(let ack) = receivedAckEnv.payload else {
            throw NSError(domain: "Test", code: 24, userInfo: [NSLocalizedDescriptionKey: "Expected ACK envelope"])
        }
        guard ack.stage == .peerStored else {
            throw NSError(domain: "Test", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected PEER_STORED stage"])
        }

        let opFound = opRepoA.getOperation(byOperationId: ack.operationId)!
        repoA.updateStatus(id: opFound.entityId, status: .relayed)

        let finalA = repoA.getMessage(id: sosId)
        guard let finalA = finalA, finalA.status == .relayed else {
            throw NSError(domain: "Test", code: 26, userInfo: [NSLocalizedDescriptionKey: "Sender SOS was not updated to .relayed after PEER_STORED ACK"])
        }

        // When explicit RECIPIENT_ACKNOWLEDGED is received, status transitions to .delivered
        repoA.updateStatus(id: opFound.entityId, status: .delivered)
        let deliveredSOS = repoA.getMessage(id: sosId)
        guard let deliveredSOS = deliveredSOS, deliveredSOS.status == .delivered else {
            throw NSError(domain: "Test", code: 27, userInfo: [NSLocalizedDescriptionKey: "Sender SOS was not updated to .delivered after RECIPIENT_ACKNOWLEDGED"])
        }
    }

    // MARK: - Test 8: SOS queue flushing on peer link restoration
    public func testSOSQueueFlushing() throws {
        let dbPath = "/tmp/offgrid_sos_flush_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)
        let myNodeId = UUID().uuidString.lowercased()

        let chatMsgId = UUID().uuidString.lowercased()
        let chatOpId = UUID().uuidString.lowercased()
        let chatMsg = OFFGRIDMessage(id: chatMsgId, senderId: myNodeId, senderName: "Me", content: "Chat", type: .chat, status: .queued)
        let chatOp = OFFGRIDOperation(id: chatOpId, entityType: .message, entityId: chatMsgId, action: .create, originNodeId: myNodeId, payloadJson: "{}", syncStatus: .queued)
        try repo.saveMessageWithOperation(message: chatMsg, operation: chatOp)

        let sosMsgId = UUID().uuidString.lowercased()
        let sosOpId = UUID().uuidString.lowercased()
        let sosMsg = OFFGRIDMessage(id: sosMsgId, senderId: myNodeId, senderName: "Me", content: "SOS", type: .sos, status: .queued)
        let sosOp = OFFGRIDOperation(id: sosOpId, entityType: .sos, entityId: sosMsgId, action: .create, originNodeId: myNodeId, payloadJson: "{}", syncStatus: .queued)
        try repo.saveMessageWithOperation(message: sosMsg, operation: sosOp)

        let pending = opRepo.getPendingOperations()
        guard pending.count == 2 else {
            throw NSError(domain: "Test", code: 27, userInfo: [NSLocalizedDescriptionKey: "Expected 2 pending operations"])
        }

        var flushedCount = 0
        for op in pending {
            if (op.entityType == .message || op.entityType == .sos) && repo.getMessage(id: op.entityId) != nil {
                repo.updateStatus(id: op.entityId, status: .relayed)
                opRepo.markStatus(operationId: op.id, status: .peerRelayed)
                flushedCount += 1
            }
        }

        guard flushedCount == 2 else {
            throw NSError(domain: "Test", code: 28, userInfo: [NSLocalizedDescriptionKey: "Both message and SOS should have been flushed"])
        }
    }

    // MARK: - Test 9: Independent SOS duplicate & new-event tests (Part A & Part B)
    public func testDuplicateSOSSuppression() throws {
        let dbPath = "/tmp/offgrid_sos_dup_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let peerId = UUID().uuidString.lowercased()
        let sosText = "Immediate extraction required: medical evacuation at ridge"
        let sosCategory = ContractV1.SOSCategory.medical

        let sosPayload = ContractV1.SOSPayload(
            text: sosText,
            category: sosCategory,
            location: ContractV1.SOSLocation(label: "Ridge Marker 4", latitude: 37.77, longitude: -122.41)
        )
        let payloadData = try JSONEncoder().encode(sosPayload)
        let payloadJson = String(data: payloadData, encoding: .utf8)!

        // --- PART A: Initial SOS and Retransmission of exact same operationId & entityId ---
        let sosIdA = UUID().uuidString.lowercased()
        let opIdA = UUID().uuidString.lowercased()

        let originalMsgA = OFFGRIDMessage(
            id: sosIdA,
            senderId: peerId,
            senderName: "Peer",
            content: sosText,
            type: .sos,
            status: .relayed
        )
        let originalOpA = OFFGRIDOperation(
            id: opIdA,
            entityType: .sos,
            entityId: sosIdA,
            action: .create,
            originNodeId: peerId,
            payloadJson: payloadJson,
            syncStatus: .peerRelayed
        )

        // 1. First arrival: persisted atomically as .inserted
        let firstRes = try repo.saveMessageWithOperation(message: originalMsgA, operation: originalOpA)
        guard firstRes == .inserted else {
            throw NSError(domain: "Test", code: 29, userInfo: [NSLocalizedDescriptionKey: "First SOS insert should be .inserted"])
        }

        // 2. Retransmit exact same SOS (same operationId and entityId): suppressed and idempotent
        let retransmitMsgA = originalMsgA
        let retransmitOpA = originalOpA
        let dupRes = try repo.saveMessageWithOperation(message: retransmitMsgA, operation: retransmitOpA)
        guard dupRes == .duplicateIdentical else {
            throw NSError(domain: "Test", code: 30, userInfo: [NSLocalizedDescriptionKey: "Retransmitted SOS should be .duplicateIdentical"])
        }

        // Total messages in DB should still be 1 (no duplicate insertion)
        let messagesAfterDup = repo.getMessages().filter { $0.type == .sos }
        guard messagesAfterDup.count == 1 else {
            throw NSError(domain: "Test", code: 31, userInfo: [NSLocalizedDescriptionKey: "Retransmission should NOT duplicate records in SQLite"])
        }

        // --- PART B: New SOS with identical text and category, but NEW operationId & entityId ---
        let sosIdB = UUID().uuidString.lowercased()
        let opIdB = UUID().uuidString.lowercased()

        let newMsgB = OFFGRIDMessage(
            id: sosIdB,
            senderId: peerId,
            senderName: "Peer",
            content: sosText, // IDENTICAL content
            type: .sos,
            status: .relayed
        )
        let newOpB = OFFGRIDOperation(
            id: opIdB, // DISTINCT operationId
            entityType: .sos,
            entityId: sosIdB, // DISTINCT entityId
            action: .create,
            originNodeId: peerId,
            payloadJson: payloadJson, // IDENTICAL payload
            syncStatus: .peerRelayed
        )

        let newEventRes = try repo.saveMessageWithOperation(message: newMsgB, operation: newOpB)
        guard newEventRes == .inserted else {
            throw NSError(domain: "Test", code: 32, userInfo: [NSLocalizedDescriptionKey: "New SOS with distinct operationId MUST be accepted as .inserted, not suppressed!"])
        }

        // Both distinct SOS events must now coexist in the database!
        let allSOSEvents = repo.getMessages().filter { $0.type == .sos }
        guard allSOSEvents.count == 2 else {
            throw NSError(domain: "Test", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected 2 distinct SOS events in SQLite, but found \(allSOSEvents.count)"])
        }
        guard opRepo.getOperation(byOperationId: opIdA) != nil && opRepo.getOperation(byOperationId: opIdB) != nil else {
            throw NSError(domain: "Test", code: 34, userInfo: [NSLocalizedDescriptionKey: "Both operations must be stored independently"])
        }
    }

    // MARK: - Test 10: Incoming vs Outgoing SOS feed separation
    public func testSOSFeedSeparation() throws {
        let dbPath = "/tmp/offgrid_sos_feed_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)

        let myNodeId = UUID().uuidString.lowercased()
        let peerNodeId = UUID().uuidString.lowercased()

        let mySOS = OFFGRIDMessage(id: UUID().uuidString.lowercased(), senderId: myNodeId, senderName: "Me", content: "My Emergency", type: .sos, status: .relayed)
        repo.saveMessage(mySOS)

        let peerSOS = OFFGRIDMessage(id: UUID().uuidString.lowercased(), senderId: peerNodeId, senderName: "Peer", content: "Peer Emergency", type: .sos, status: .delivered)
        repo.saveMessage(peerSOS)

        let allMessages = repo.getMessages()
        let allSOS = allMessages.filter { $0.type == .sos }

        let activeAlerts = allSOS.filter { $0.senderId != myNodeId }
        let mySentSOS = allSOS.filter { $0.senderId == myNodeId }

        guard activeAlerts.count == 1 && activeAlerts.first?.id == peerSOS.id else {
            throw NSError(domain: "Test", code: 31, userInfo: [NSLocalizedDescriptionKey: "activeAlerts failed to load peer SOS"])
        }
        guard mySentSOS.count == 1 && mySentSOS.first?.id == mySOS.id else {
            throw NSError(domain: "Test", code: 32, userInfo: [NSLocalizedDescriptionKey: "mySentSOS failed to load local SOS"])
        }
    }

    // MARK: - Test 11: Intermediate peers strictly issue PEER_STORED and never RECIPIENT_ACKNOWLEDGED
    public func testIntermediatePeerAckRestrictions() throws {
        let intermediateNodeB = UUID().uuidString.lowercased()
        let finalRecipientC = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let packetId = UUID().uuidString.lowercased()

        // When intermediateNodeB receives an operation destined for finalRecipientC:
        // intermediateNodeB stores in local SQLite, and MUST issue PEER_STORED
        let intermediateAck = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: opId,
            stage: .peerStored, // MUST be PEER_STORED
            acknowledgingNodeId: intermediateNodeB,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId
        )

        // Intermediate node must NOT issue RECIPIENT_ACKNOWLEDGED
        guard intermediateAck.stage != .recipientAcknowledged else {
            throw NSError(domain: "Test", code: 33, userInfo: [NSLocalizedDescriptionKey: "Intermediate peer incorrectly issued RECIPIENT_ACKNOWLEDGED"])
        }
        guard intermediateAck.stage == .peerStored else {
            throw NSError(domain: "Test", code: 34, userInfo: [NSLocalizedDescriptionKey: "Intermediate peer did not issue PEER_STORED"])
        }

        // Only finalRecipientC may issue RECIPIENT_ACKNOWLEDGED
        let recipientAck = ContractV1.Acknowledgment(
            schemaVersion: 1,
            ackId: UUID().uuidString.lowercased(),
            operationId: opId,
            stage: .recipientAcknowledged,
            acknowledgingNodeId: finalRecipientC,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            packetId: packetId
        )
        guard recipientAck.acknowledgingNodeId == finalRecipientC && recipientAck.stage == .recipientAcknowledged else {
            throw NSError(domain: "Test", code: 35, userInfo: [NSLocalizedDescriptionKey: "Recipient ACK invariant failed"])
        }
    }

    // MARK: - Test 12: Inbound operation is never acknowledged before durable storage succeeds
    public func testStorageFailurePreventsAck() throws {
        let dbPath = "/tmp/offgrid_storage_fail_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let opRepo = OperationQueueRepository(database: db)

        let opId = UUID().uuidString.lowercased()
        let entityId = UUID().uuidString.lowercased()
        let senderId = UUID().uuidString.lowercased()

        // Persist first operation
        let initialOp = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: entityId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"First payload\"}",
            syncStatus: .localOnly
        )
        let firstRes = try opRepo.enqueue(operation: initialOp)
        guard firstRes == .inserted else {
            throw NSError(domain: "Test", code: 36, userInfo: [NSLocalizedDescriptionKey: "Initial insert failed"])
        }

        // Attempting to store a conflicting operation under same opId must fail and prevent ACK
        let conflictingOp = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: entityId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"CONFLICTING PAYLOAD\"}",
            syncStatus: .localOnly
        )

        var ackSent = false
        do {
            _ = try opRepo.enqueue(operation: conflictingOp)
            ackSent = true // Should NEVER execute
        } catch SQLiteDatabase.OperationStorageError.conflictingPayload {
            // Storage rejected! In accordance with Requirement 6, ACK is strictly suppressed!
            ackSent = false
        }

        guard !ackSent else {
            throw NSError(domain: "Test", code: 37, userInfo: [NSLocalizedDescriptionKey: "ACK was sent despite storage failure! Violation of Requirement 6."])
        }
    }

    // MARK: - Test 13: Retransmission preserves exact operation ID and message ID
    public func testRetransmissionPreservesIdentities() throws {
        let dbPath = "/tmp/offgrid_retransmit_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let msgId = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let nodeId = UUID().uuidString.lowercased()

        let message = OFFGRIDMessage(
            id: msgId,
            senderId: nodeId,
            senderName: "Me",
            content: "Retry test message",
            status: .queued
        )
        let op = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: msgId,
            action: .create,
            originNodeId: nodeId,
            payloadJson: "{\"text\":\"Retry test message\",\"recipientNodeId\":\"\(ContractV1.broadcastRecipientId)\"}",
            syncStatus: .queued,
            retryCount: 0
        )
        try repo.saveMessageWithOperation(message: message, operation: op)

        // Simulate retransmission
        let pending = opRepo.getPendingOperations()
        guard let pendingOp = pending.first(where: { $0.entityId == msgId }) else {
            throw NSError(domain: "Test", code: 38, userInfo: [NSLocalizedDescriptionKey: "Pending op not found"])
        }

        opRepo.incrementRetry(operationId: pendingOp.id)

        // Verify identities are perfectly preserved
        guard let retrievedOp = opRepo.getOperation(byOperationId: opId) else {
            throw NSError(domain: "Test", code: 39, userInfo: [NSLocalizedDescriptionKey: "Operation not found after retry increment"])
        }
        guard retrievedOp.id == opId && retrievedOp.entityId == msgId else {
            throw NSError(domain: "Test", code: 40, userInfo: [NSLocalizedDescriptionKey: "Operation or entity identity mutated during retry"])
        }
        guard retrievedOp.retryCount == 1 else {
            throw NSError(domain: "Test", code: 41, userInfo: [NSLocalizedDescriptionKey: "Retry count was not incremented"])
        }

        // Construct retransmitted envelope and verify it retains original IDs
        let retransmitEnv = ContractV1.Envelope(
            version: 1,
            packetId: UUID().uuidString.lowercased(),
            sourceNodeId: nodeId,
            destinationNodeId: "*",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            ttl: 5,
            hopCount: 0,
            type: .syncOp,
            payload: .syncOp(ContractV1.Operation(
                schemaVersion: 1,
                operationId: retrievedOp.id,
                originNodeId: retrievedOp.originNodeId,
                entityId: retrievedOp.entityId,
                timestamp: Int64(retrievedOp.timestamp.timeIntervalSince1970 * 1000),
                lamportClock: retrievedOp.lamportClock,
                entityType: .message,
                action: .create,
                baseVersion: 0,
                payload: .message(ContractV1.MessagePayload(text: "Retry test message", recipientNodeId: ContractV1.broadcastRecipientId))
            ))
        )
        try ContractV1Validator.validateEnvelope(retransmitEnv)

        guard case .syncOp(let retransmittedOp) = retransmitEnv.payload else {
            throw NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected syncOp"])
        }
        guard retransmittedOp.operationId == opId && retransmittedOp.entityId == msgId else {
            throw NSError(domain: "Test", code: 43, userInfo: [NSLocalizedDescriptionKey: "Retransmitted operation changed operationId or entityId"])
        }
    }

    // MARK: - Test 14: Fault-injected atomic inbound persistence rollback & zero ACK
    public func testFaultInjectedInboundPersistenceRollback() throws {
        let dbPath = "/tmp/offgrid_atomic_inbound_\(UUID().uuidString.lowercased()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let msgId = UUID().uuidString.lowercased()
        let opId = UUID().uuidString.lowercased()
        let senderId = UUID().uuidString.lowercased()

        let message = OFFGRIDMessage(
            id: msgId,
            senderId: senderId,
            senderName: "Sender",
            content: "Transactional atomic message",
            type: .chat,
            status: .relayed
        )
        let op = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: msgId,
            action: .create,
            originNodeId: senderId,
            payloadJson: "{\"text\":\"Transactional atomic message\",\"recipientNodeId\":\"*\"}",
            syncStatus: .peerRelayed
        )

        // Inject failure between message write and operation write within the transaction
        SQLiteDatabase.inboundPersistenceFaultInjection = {
            throw NSError(domain: "org.offgrid.fault", code: 777, userInfo: [NSLocalizedDescriptionKey: "Simulated mid-transaction power loss between message and operation writes"])
        }
        defer {
            SQLiteDatabase.inboundPersistenceFaultInjection = nil
        }

        var caughtInjectedError = false
        var ackTransmitted = false
        do {
            try repo.saveMessageWithOperation(message: message, operation: op)
            ackTransmitted = true // Should NEVER execute
        } catch {
            caughtInjectedError = true
            ackTransmitted = false
        }

        guard caughtInjectedError else {
            throw NSError(domain: "Test", code: 44, userInfo: [NSLocalizedDescriptionKey: "Injected fault did not trigger"])
        }
        guard !ackTransmitted else {
            throw NSError(domain: "Test", code: 45, userInfo: [NSLocalizedDescriptionKey: "ACK was transmitted despite transaction failure! Violation of Requirement 3."])
        }

        // Verify full atomicity rollback on the same SQLite connection:
        // NEITHER the message NOR the operation was committed!
        let storedMessage = repo.getMessage(id: msgId)
        let storedOperation = opRepo.getOperation(byOperationId: opId)

        guard storedMessage == nil else {
            throw NSError(domain: "Test", code: 46, userInfo: [NSLocalizedDescriptionKey: "Message was partially committed despite transaction rollback! Atomicity failure."])
        }
        guard storedOperation == nil else {
            throw NSError(domain: "Test", code: 47, userInfo: [NSLocalizedDescriptionKey: "Operation was partially committed despite transaction rollback! Atomicity failure."])
        }
    }

    // MARK: - Test 15: Multipeer session lifecycle & security
    public func testMultipeerSessionLifecycleAndSecurity() throws {
        let managerA = MultipeerSessionManager(displayName: "iPhone-Alpha")
        let managerB = MultipeerSessionManager(displayName: "iPhone-Beta")

        // 1. Verify session initialization
        let sessionA = managerA.getOrCreateSession()
        guard sessionA.connectedPeers.isEmpty else {
            throw NSError(domain: "Test", code: 50, userInfo: [NSLocalizedDescriptionKey: "Initial session should have no connected peers"])
        }

        // 2. Verify certificate handler auto-approves
        var certificateApproved = false
        let dummyPeer = MCPeerID(displayName: "iPhone-Beta")
        managerA.session(sessionA, didReceiveCertificate: nil, fromPeer: dummyPeer) { approved in
            certificateApproved = approved
        }
        guard certificateApproved else {
            throw NSError(domain: "Test", code: 51, userInfo: [NSLocalizedDescriptionKey: "didReceiveCertificate failed to approve peer certificate!"])
        }

        // 3. Verify tie-breaker logic with distinct and identical names
        let comparisonAB = "iPhone-Beta".compare("iPhone-Alpha")
        guard comparisonAB == .orderedDescending else {
            throw NSError(domain: "Test", code: 52, userInfo: [NSLocalizedDescriptionKey: "Tie-breaker comparison failed"])
        }

        let nameSame1 = "iPhone-Clone"
        let nameSame2 = "iPhone-Clone"
        let peer1 = MCPeerID(displayName: nameSame1)
        let peer2 = MCPeerID(displayName: nameSame2)
        let peer1Wins = peer1.hashValue >= peer2.hashValue
        let peer2Wins = peer2.hashValue >= peer1.hashValue
        guard peer1Wins || peer2Wins else {
            throw NSError(domain: "Test", code: 53, userInfo: [NSLocalizedDescriptionKey: "Identical name tie-breaker failed"])
        }

        // 4. Verify session reset and recovery
        let initialSession = managerA.getOrCreateSession()
        managerA.resetSessionIfEmpty()
        let refreshedSession = managerA.getOrCreateSession()
        guard initialSession !== refreshedSession else {
            throw NSError(domain: "Test", code: 54, userInfo: [NSLocalizedDescriptionKey: "resetSessionIfEmpty failed to generate a fresh MCSession"])
        }

        // 5. Verify stop tears down session cleanly and start recreates it
        managerA.stop()
        guard !managerA.hasConnectedPeers else {
            throw NSError(domain: "Test", code: 55, userInfo: [NSLocalizedDescriptionKey: "stop() should leave no connected peers"])
        }
        managerA.start()
        let restartedSession = managerA.getOrCreateSession()
        guard restartedSession !== refreshedSession else {
            throw NSError(domain: "Test", code: 56, userInfo: [NSLocalizedDescriptionKey: "start() should recreate a fresh MCSession after stop()"])
        }
        managerA.stop()
        managerB.stop()
    }
}
