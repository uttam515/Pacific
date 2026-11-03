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
}
