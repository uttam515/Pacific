import Foundation

public final class SyncEngine: @unchecked Sendable {
    private let operationRepository: OperationQueueRepository
    private let messageRepository: MessageRepository
    private let session: URLSession
    private var gatewayBaseURL: URL?

    public init(
        operationRepository: OperationQueueRepository = OperationQueueRepository(),
        messageRepository: MessageRepository = MessageRepository(),
        session: URLSession = .shared,
        gatewayURLString: String? = nil
    ) {
        self.operationRepository = operationRepository
        self.messageRepository = messageRepository
        self.session = session
        if let urlStr = gatewayURLString {
            self.gatewayBaseURL = URL(string: urlStr)
        }
    }

    public func setGatewayURL(_ urlString: String) {
        self.gatewayBaseURL = URL(string: urlString)
    }

    public func syncPendingOperations() async {
        guard let gatewayURL = gatewayBaseURL else { return }

        let pendingOps = operationRepository.getPendingOperations()
        guard !pendingOps.isEmpty else { return }

        let pushURL = gatewayURL.appendingPathComponent("api/v1/sync/push")
        var request = URLRequest(url: pushURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let requestBody: [String: Any] = [
                "nodeId": KeychainHelper.shared.getOrCreateNodeId(),
                "operations": pendingOps.map { [
                    "operationId": $0.id,
                    "entityType": $0.entityType.rawValue,
                    "action": $0.action.rawValue,
                    "timestamp": Int64($0.timestamp.timeIntervalSince1970 * 1000),
                    "lamportClock": $0.lamportClock,
                    "payload": $0.payloadJson
                ]}
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let acceptedIds = json["acceptedIds"] as? [String] {
                    for opId in acceptedIds {
                        operationRepository.markStatus(operationId: opId, status: .gatewaySynced)
                        // Also update corresponding message entity if applicable
                        if let op = operationRepository.getOperation(id: opId), op.entityType == .message {
                            messageRepository.updateStatus(id: op.entityId, status: .synced)
                        }
                    }
                }
            }
        } catch {
            print("[SyncEngine] Sync failed: \(error.localizedDescription)")
        }
    }
}
