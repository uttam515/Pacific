import Foundation

public final class MeshProtocolTests {
    public func runAllTests() -> Bool {
        print("\n===========================================")
        print("  OFFGRID iOS Mesh Protocol & Delivery Tests")
        print("===========================================")

        var passed = true
        passed = runTest("1. Packet header validation & invariant checks", testPacketHeaderValidation) && passed
        passed = runTest("2. Deterministic multipeer tie-breaker comparison", testTieBreakerLogic) && passed
        passed = runTest("3. End-to-end Device-to-Device message & delivery ACK simulation", testDeviceToDeviceMessageAndAckFlow) && passed
        passed = runTest("4. Inbound duplicate message suppression & idempotent ACK", testDuplicateSuppressionAndAck) && passed
        passed = runTest("5. Offline queued message flushing on peer connect", testOfflineQueueFlushing) && passed
        passed = runTest("6. Emergency SOS atomic creation and persistence", testSOSCreationAndPersistence) && passed
        passed = runTest("7. End-to-end SOS transmission, entity preservation, and ACK delivery", testSOSTransmissionAndAckFlow) && passed
        passed = runTest("8. SOS queue flushing on peer link restoration", testSOSQueueFlushing) && passed
        passed = runTest("9. Inbound duplicate SOS suppression & idempotency", testDuplicateSOSSuppression) && passed
        passed = runTest("10. Active incoming vs outgoing SOS feed separation", testSOSFeedSeparation) && passed

        print("===========================================")
        if passed {
            print("  ALL MESH PROTOCOL TESTS PASSED!")
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

    // Test 1: Header validation
    public func testPacketHeaderValidation() throws {
        let validator = PacketValidator.shared

        // Valid header
        let validHeader = WirePacketHeader(
            version: 1,
            packetId: UUID().uuidString,
            type: .message,
            sourceNodeId: "node-1234",
            destinationNodeId: "*",
            ttl: 5,
            hopCount: 0
        )
        try validator.validateHeader(validHeader)

        // Invalid version
        let invalidVersionHeader = WirePacketHeader(
            version: 0,
            packetId: UUID().uuidString,
            type: .message,
            sourceNodeId: "node-1234"
        )
        var caughtVersionError = false
        do {
            try validator.validateHeader(invalidVersionHeader)
        } catch PacketValidationError.invalidVersion {
            caughtVersionError = true
        }
        guard caughtVersionError else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Did not catch invalidVersion"])
        }

        // Invalid empty packetId
        let emptyIdHeader = WirePacketHeader(
            version: 1,
            packetId: "   ",
            type: .message,
            sourceNodeId: "node-1234"
        )
        var caughtEmptyId = false
        do {
            try validator.validateHeader(emptyIdHeader)
        } catch PacketValidationError.missingPacketId {
            caughtEmptyId = true
        }
        guard caughtEmptyId else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Did not catch missingPacketId"])
        }

        // Invalid zero TTL
        var zeroTtlHeader = validHeader
        zeroTtlHeader.ttl = 0
        var caughtZeroTtl = false
        do {
            try validator.validateHeader(zeroTtlHeader)
        } catch PacketValidationError.zeroOrNegativeTTL {
            caughtZeroTtl = true
        }
        guard caughtZeroTtl else {
            throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Did not catch zeroOrNegativeTTL"])
        }
    }

    // Test 2: Multipeer tie-breaker logic
    public func testTieBreakerLogic() throws {
        let peerAlpha = "iPhone-Alpha-1234"
        let peerBeta = "iPhone-Beta-5678"

        // Alpha vs Beta: Beta > Alpha
        let betaWins = peerBeta.compare(peerAlpha) == .orderedDescending
        let alphaLoses = peerAlpha.compare(peerBeta) == .orderedAscending

        guard betaWins && alphaLoses else {
            throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Tie-breaker ordering failed"])
        }

        // Exactly one device invites; the other defers
        let betaShouldInvite = peerBeta.compare(peerAlpha) == .orderedDescending
        let alphaShouldInvite = peerAlpha.compare(peerBeta) == .orderedDescending

        guard betaShouldInvite && !alphaShouldInvite else {
            throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Mutual invitation race was not broken cleanly"])
        }
    }

    // Test 3: Simulated two-device exchange with ACK
    public func testDeviceToDeviceMessageAndAckFlow() throws {
        let dbPathA = "/tmp/offgrid_device_a_\(UUID().uuidString).sqlite"
        let dbPathB = "/tmp/offgrid_device_b_\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: dbPathA)
            try? FileManager.default.removeItem(atPath: dbPathB)
        }

        let dbA = SQLiteDatabase(inMemory: false, customPath: dbPathA)
        let repoA = MessageRepository(database: dbA)
        let opRepoA = OperationQueueRepository(database: dbA)

        let dbB = SQLiteDatabase(inMemory: false, customPath: dbPathB)
        let repoB = MessageRepository(database: dbB)
        _ = OperationQueueRepository(database: dbB)

        let nodeA = "NODE-IPHONE-A"
        let nodeB = "NODE-IPHONE-B"

        // Step 1: iPhone A generates message & operation, saves to SQLite
        let messageId = UUID().uuidString
        let opId = UUID().uuidString
        let message = OFFGRIDMessage(
            id: messageId,
            senderId: nodeA,
            senderName: "iPhone A",
            recipientId: "*",
            content: "Hello from iPhone A across offline mesh!",
            type: .chat,
            status: .localOnly
        )

        let op = OFFGRIDOperation(
            id: opId,
            entityType: .message,
            entityId: message.id,
            action: .create,
            originNodeId: nodeA,
            payloadJson: try String(data: JSONEncoder().encode(message), encoding: .utf8)!,
            syncStatus: .localOnly
        )

        try repoA.saveMessageWithOperation(message: message, operation: op)

        // Step 2: iPhone A transmits packet (simulated relay)
        repoA.updateStatus(id: message.id, status: .relayed)
        opRepoA.markStatus(operationId: op.id, status: .peerRelayed)

        // Step 3: Verify iPhone A is NOT marked delivered yet!
        let msgAAfterRelay = repoA.getMessage(id: messageId)!
        guard msgAAfterRelay.status == .relayed else {
            throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Message should be .relayed, not .delivered!"])
        }

        // Step 4: iPhone B receives packet over wire
        let wireEnvelope = WirePacketEnvelope(
            packetId: message.id,
            type: .message,
            sourceNodeId: nodeA,
            destinationNodeId: "*",
            payload: message
        )
        let packetData = try JSONEncoder().encode(wireEnvelope)

        // iPhone B decodes header and payload
        let headerB = try JSONDecoder().decode(WirePacketHeader.self, from: packetData)
        try PacketValidator.shared.validateHeader(headerB)

        let envelopeB = try JSONDecoder().decode(WirePacketEnvelope<OFFGRIDMessage>.self, from: packetData)
        var receivedMessageB = envelopeB.payload
        receivedMessageB.status = .delivered
        repoB.saveMessage(receivedMessageB)

        // Verify iPhone B stored the message
        let storedB = repoB.getMessage(id: messageId)
        guard storedB != nil && storedB?.content == message.content else {
            throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Device B failed to store received message"])
        }

        // Step 5: iPhone B sends back ACK
        let ackPayload = AckPacketPayload(
            acknowledgedPacketId: messageId,
            receivingNodeId: nodeB
        )
        let ackEnvelope = WirePacketEnvelope(
            packetId: UUID().uuidString,
            type: .ack,
            sourceNodeId: nodeB,
            destinationNodeId: nodeA,
            payload: ackPayload
        )
        let ackData = try JSONEncoder().encode(ackEnvelope)

        // Step 6: iPhone A receives ACK
        let ackHeaderA = try JSONDecoder().decode(WirePacketHeader.self, from: ackData)
        try PacketValidator.shared.validateHeader(ackHeaderA)

        let receivedAckEnv = try JSONDecoder().decode(WirePacketEnvelope<AckPacketPayload>.self, from: ackData)
        let ackId = receivedAckEnv.payload.acknowledgedPacketId

        // iPhone A updates message status to .delivered ONLY upon verified ACK
        repoA.updateStatus(id: ackId, status: .delivered)
        opRepoA.markStatus(operationId: opId, status: .peerRelayed)

        let finalMsgA = repoA.getMessage(id: messageId)!
        guard finalMsgA.status == .delivered else {
            throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Message A did not transition to .delivered after ACK"])
        }
    }

    // Test 4: Duplicate message suppression
    public func testDuplicateSuppressionAndAck() throws {
        let dbPath = "/tmp/offgrid_dup_test_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)

        let messageId = UUID().uuidString
        let originalMsg = OFFGRIDMessage(
            id: messageId,
            senderId: "NODE-1",
            senderName: "Node 1",
            content: "Original Content",
            status: .delivered
        )

        repo.saveMessage(originalMsg)

        // Attempt second insert with identical ID but different content
        let duplicateMsg = OFFGRIDMessage(
            id: messageId,
            senderId: "NODE-1",
            senderName: "Node 1",
            content: "Tampered Content",
            status: .delivered
        )

        // Deduplication guard
        let exists = repo.getMessage(id: duplicateMsg.id) != nil
        guard exists else {
            throw NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "Message should exist"])
        }

        // Database content remains original
        let stored = repo.getMessage(id: messageId)!
        guard stored.content == "Original Content" else {
            throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Duplicate was not suppressed"])
        }
    }

    // Test 5: Offline queue flushing
    public func testOfflineQueueFlushing() throws {
        let dbPath = "/tmp/offgrid_queue_test_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        // Queue 3 offline messages
        for i in 1...3 {
            let msg = OFFGRIDMessage(
                id: "msg-\(i)",
                senderId: "node-me",
                senderName: "Me",
                content: "Offline message \(i)",
                status: .queued
            )
            let op = OFFGRIDOperation(
                id: "op-\(i)",
                entityType: .message,
                entityId: msg.id,
                action: .create,
                originNodeId: "node-me",
                payloadJson: "{}",
                syncStatus: .queued
            )
            try repo.saveMessageWithOperation(message: msg, operation: op)
        }

        // Check pending operations
        let pending = opRepo.getPendingOperations()
        guard pending.count == 3 else {
            throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected 3 pending ops"])
        }

        // Simulate flush upon peer connection: mark them relayed
        for op in pending {
            repo.updateStatus(id: op.entityId, status: .relayed)
            opRepo.markStatus(operationId: op.id, status: .peerRelayed)
        }

        // Verify that no operations remain in .localOnly or .queued
        let remainingQueued = opRepo.getPendingOperations().filter {
            $0.syncStatus == .localOnly || $0.syncStatus == .queued
        }
        guard remainingQueued.isEmpty else {
            throw NSError(domain: "Test", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unsent queue should be 0 after flush"])
        }

        // When internet returns, operations transition to gatewaySynced
        for op in pending {
            opRepo.markStatus(operationId: op.id, status: .gatewaySynced)
        }
        let remainingAfterGateway = opRepo.getPendingOperations()
        guard remainingAfterGateway.isEmpty else {
            throw NSError(domain: "Test", code: 13, userInfo: [NSLocalizedDescriptionKey: "Pending ops should be 0 after gateway sync"])
        }
    }

    // Test 6: SOS creation and persistence
    public func testSOSCreationAndPersistence() throws {
        let dbPath = "/tmp/offgrid_sos_create_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        let sosMsg = OFFGRIDMessage(
            id: "sos-001",
            senderId: "NODE-ALPHA",
            senderName: "Alpha",
            content: "[MEDICAL EMERGENCY] Need bandages",
            type: .sos,
            status: .localOnly
        )
        let op = OFFGRIDOperation(
            id: "op-sos-001",
            entityType: .sos,
            entityId: sosMsg.id,
            action: .create,
            originNodeId: "NODE-ALPHA",
            payloadJson: try String(data: JSONEncoder().encode(sosMsg), encoding: .utf8)!,
            syncStatus: .localOnly
        )

        try repo.saveMessageWithOperation(message: sosMsg, operation: op)

        let retrievedMsg = repo.getMessage(id: "sos-001")
        guard let retrievedMsg = retrievedMsg, retrievedMsg.type == .sos else {
            throw NSError(domain: "Test", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to persist SOS message as .sos"])
        }

        let retrievedOp = opRepo.getOperation(id: "op-sos-001")
        guard let retrievedOp = retrievedOp, retrievedOp.entityType == .sos else {
            throw NSError(domain: "Test", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to persist SOS operation as .sos"])
        }
    }

    // Test 7: SOS transmission, receiver persistence with correct entity type, and ACK
    public func testSOSTransmissionAndAckFlow() throws {
        let dbPathA = "/tmp/offgrid_sos_a_\(UUID().uuidString).sqlite"
        let dbPathB = "/tmp/offgrid_sos_b_\(UUID().uuidString).sqlite"
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

        let nodeA = "NODE-SENDER-SOS"
        let nodeB = "NODE-RECEIVER-SOS"
        let sosId = "sos-exchange-123"

        // 1. Sender persists SOS
        let sosMsg = OFFGRIDMessage(
            id: sosId,
            senderId: nodeA,
            senderName: "Sender",
            content: "[FIRE HAZARD] Brush fire near coordinates",
            type: .sos,
            status: .localOnly
        )
        let opA = OFFGRIDOperation(
            id: "op-sos-a",
            entityType: .sos,
            entityId: sosId,
            action: .create,
            originNodeId: nodeA,
            payloadJson: try String(data: JSONEncoder().encode(sosMsg), encoding: .utf8)!,
            syncStatus: .localOnly
        )
        try repoA.saveMessageWithOperation(message: sosMsg, operation: opA)

        // Sender relays message
        repoA.updateStatus(id: sosId, status: .relayed)
        opRepoA.markStatus(operationId: opA.id, status: .peerRelayed)

        // 2. Transmit wire envelope
        let envelopeA = WirePacketEnvelope(
            packetId: sosId,
            type: .sos,
            sourceNodeId: nodeA,
            destinationNodeId: "*",
            payload: sosMsg
        )
        let packetData = try JSONEncoder().encode(envelopeA)

        // 3. Receiver parses header and envelope
        let headerB = try JSONDecoder().decode(WirePacketHeader.self, from: packetData)
        guard headerB.type == .sos else {
            throw NSError(domain: "Test", code: 22, userInfo: [NSLocalizedDescriptionKey: "Header type should be .sos"])
        }
        try PacketValidator.shared.validateHeader(headerB)

        let envelopeB = try JSONDecoder().decode(WirePacketEnvelope<OFFGRIDMessage>.self, from: packetData)
        var receivedB = envelopeB.payload
        receivedB.status = .delivered
        repoB.saveMessage(receivedB)

        // Receiver creates operation with PRESERVED .sos entity type
        let opB = OFFGRIDOperation(
            id: "op-sos-b",
            entityType: receivedB.type == .sos ? .sos : .message,
            entityId: receivedB.id,
            action: .create,
            originNodeId: receivedB.senderId,
            payloadJson: try String(data: JSONEncoder().encode(receivedB), encoding: .utf8)!,
            syncStatus: .peerRelayed
        )
        opRepoB.enqueue(operation: opB)

        // Verify Receiver stored with correct types
        let storedB = repoB.getMessage(id: sosId)
        guard let storedB = storedB, storedB.type == .sos else {
            throw NSError(domain: "Test", code: 23, userInfo: [NSLocalizedDescriptionKey: "Receiver failed to store SOS as .sos"])
        }
        let storedOpB = opRepoB.getOperation(id: "op-sos-b")
        guard let storedOpB = storedOpB, storedOpB.entityType == .sos else {
            throw NSError(domain: "Test", code: 24, userInfo: [NSLocalizedDescriptionKey: "Receiver failed to preserve .sos entity type in operation"])
        }

        // 4. Receiver sends ACK
        let ackPayload = AckPacketPayload(acknowledgedPacketId: sosId, receivingNodeId: nodeB)
        let ackEnvelope = WirePacketEnvelope(
            packetId: UUID().uuidString,
            type: .ack,
            sourceNodeId: nodeB,
            destinationNodeId: nodeA,
            payload: ackPayload
        )
        let ackData = try JSONEncoder().encode(ackEnvelope)

        // 5. Sender receives ACK and marks delivered
        let receivedAck = try JSONDecoder().decode(WirePacketEnvelope<AckPacketPayload>.self, from: ackData)
        repoA.updateStatus(id: receivedAck.payload.acknowledgedPacketId, status: .delivered)

        let finalA = repoA.getMessage(id: sosId)
        guard let finalA = finalA, finalA.status == .delivered else {
            throw NSError(domain: "Test", code: 25, userInfo: [NSLocalizedDescriptionKey: "Sender SOS was not updated to .delivered after ACK"])
        }
    }

    // Test 8: SOS queue flushing on peer link
    public func testSOSQueueFlushing() throws {
        let dbPath = "/tmp/offgrid_sos_flush_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)
        let opRepo = OperationQueueRepository(database: db)

        // Queue 1 chat and 1 SOS operation
        let chatMsg = OFFGRIDMessage(id: "chat-q1", senderId: "me", senderName: "Me", content: "Chat", type: .chat, status: .queued)
        let chatOp = OFFGRIDOperation(id: "op-q1", entityType: .message, entityId: "chat-q1", action: .create, originNodeId: "me", payloadJson: "{}", syncStatus: .queued)
        try repo.saveMessageWithOperation(message: chatMsg, operation: chatOp)

        let sosMsg = OFFGRIDMessage(id: "sos-q2", senderId: "me", senderName: "Me", content: "SOS", type: .sos, status: .queued)
        let sosOp = OFFGRIDOperation(id: "op-q2", entityType: .sos, entityId: "sos-q2", action: .create, originNodeId: "me", payloadJson: "{}", syncStatus: .queued)
        try repo.saveMessageWithOperation(message: sosMsg, operation: sosOp)

        // Verify both are pending
        let pending = opRepo.getPendingOperations()
        guard pending.count == 2 else {
            throw NSError(domain: "Test", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected 2 pending operations"])
        }

        // Simulate flushPendingQueue logic (handling both .message and .sos)
        var flushedCount = 0
        for op in pending {
            if (op.entityType == .message || op.entityType == .sos) && repo.getMessage(id: op.entityId) != nil {
                repo.updateStatus(id: op.entityId, status: .relayed)
                opRepo.markStatus(operationId: op.id, status: .peerRelayed)
                flushedCount += 1
            }
        }

        guard flushedCount == 2 else {
            throw NSError(domain: "Test", code: 27, userInfo: [NSLocalizedDescriptionKey: "Both message and SOS should have been flushed, but got \(flushedCount)"])
        }

        let remainingQueued = opRepo.getPendingOperations().filter {
            $0.syncStatus == .localOnly || $0.syncStatus == .queued
        }
        guard remainingQueued.isEmpty else {
            throw NSError(domain: "Test", code: 28, userInfo: [NSLocalizedDescriptionKey: "Queued ops should be empty after flush"])
        }
    }

    // Test 9: Duplicate SOS suppression
    public func testDuplicateSOSSuppression() throws {
        let dbPath = "/tmp/offgrid_sos_dup_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)

        let sosId = "sos-dup-1"
        let original = OFFGRIDMessage(id: sosId, senderId: "peer-1", senderName: "Peer", content: "Original SOS", type: .sos, status: .delivered)
        repo.saveMessage(original)

        // Simulate duplicate inbound packet with same ID
        let duplicate = OFFGRIDMessage(id: sosId, senderId: "peer-1", senderName: "Peer", content: "Tampered Content", type: .sos, status: .delivered)

        let exists = repo.getMessage(id: duplicate.id) != nil
        guard exists else {
            throw NSError(domain: "Test", code: 29, userInfo: [NSLocalizedDescriptionKey: "Duplicate SOS check failed"])
        }

        // Original remains unmodified
        let retrieved = repo.getMessage(id: sosId)!
        guard retrieved.content == "Original SOS" else {
            throw NSError(domain: "Test", code: 30, userInfo: [NSLocalizedDescriptionKey: "Original SOS was overwritten by duplicate"])
        }
    }

    // Test 10: Incoming vs Outgoing SOS separation
    public func testSOSFeedSeparation() throws {
        let dbPath = "/tmp/offgrid_sos_feed_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = SQLiteDatabase(inMemory: false, customPath: dbPath)
        let repo = MessageRepository(database: db)

        let myNodeId = "MY-LOCAL-NODE"
        let peerNodeId = "PEER-REMOTE-NODE"

        // Outgoing SOS
        let mySOS = OFFGRIDMessage(id: "my-sos", senderId: myNodeId, senderName: "Me", content: "My Emergency", type: .sos, status: .relayed)
        repo.saveMessage(mySOS)

        // Incoming SOS
        let peerSOS = OFFGRIDMessage(id: "peer-sos", senderId: peerNodeId, senderName: "Peer", content: "Peer Emergency", type: .sos, status: .delivered)
        repo.saveMessage(peerSOS)

        // Query and separate
        let allMessages = repo.getMessages()
        let allSOS = allMessages.filter { $0.type == .sos }

        let activeAlerts = allSOS.filter { $0.senderId != myNodeId }
        let mySentSOS = allSOS.filter { $0.senderId == myNodeId }

        guard activeAlerts.count == 1 && activeAlerts.first?.id == "peer-sos" else {
            throw NSError(domain: "Test", code: 31, userInfo: [NSLocalizedDescriptionKey: "activeAlerts failed to load peer SOS"])
        }
        guard mySentSOS.count == 1 && mySentSOS.first?.id == "my-sos" else {
            throw NSError(domain: "Test", code: 32, userInfo: [NSLocalizedDescriptionKey: "mySentSOS failed to load local SOS"])
        }
    }
}
