import Foundation

/// Manages peer trust, consent-based pairing, rate limiting, and location privacy.
public final class PeerTrustManager: @unchecked Sendable {
    public static let shared = PeerTrustManager()

    private let lock = NSRecursiveLock()
    private var trustedNodeIds = Set<String>()
    private var peerPacketTimestamps: [String: [Date]] = [:]

    /// When true, allows all discovered peers for development/testing mesh.
    /// In production mode, strictly requires explicit pairing or verification.
    #if DEBUG
    public var isDevelopmentMode: Bool = true
    #else
    public var isDevelopmentMode: Bool = false
    #endif
    public let maxPacketsPerMinute: Int = 60

    public init() {}

    public func trustPeer(nodeId: String) {
        lock.lock()
        defer { lock.unlock() }
        trustedNodeIds.insert(nodeId.lowercased())
    }

    public func untrustPeer(nodeId: String) {
        lock.lock()
        defer { lock.unlock() }
        trustedNodeIds.remove(nodeId.lowercased())
    }

    public func isPeerTrusted(nodeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isDevelopmentMode { return true }
        return trustedNodeIds.contains(nodeId.lowercased())
    }

    /// Evaluates sliding-window rate limit for a peer (DoS and packet flooding prevention)
    public func isRateLimited(nodeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60.0)

        var timestamps = peerPacketTimestamps[nodeId.lowercased()] ?? []
        timestamps = timestamps.filter { $0 > oneMinuteAgo }

        if timestamps.count >= maxPacketsPerMinute {
            peerPacketTimestamps[nodeId.lowercased()] = timestamps
            return true
        }

        timestamps.append(now)
        peerPacketTimestamps[nodeId.lowercased()] = timestamps
        return false
    }

    /// Strips sensitive location data from packets unless explicitly authorized as an Emergency SOS
    public func sanitizeLocationIfNeeded(op: ContractV1.Operation) -> ContractV1.Operation {
        guard op.entityType == .sos, case .sos(let sosPayload) = op.payload else {
            return op
        }

        // If peer is not explicitly trusted and not in development mode, strip precise GPS coordinates
        if !isPeerTrusted(nodeId: op.originNodeId) && !isDevelopmentMode {
            let coarsenedLocation = ContractV1.SOSLocation(
                label: sosPayload.location.label,
                latitude: nil,
                longitude: nil
            )
            let coarsenedPayload = ContractV1.SOSPayload(
                text: sosPayload.text,
                category: sosPayload.category,
                location: coarsenedLocation
            )
            return ContractV1.Operation(
                schemaVersion: op.schemaVersion,
                operationId: op.operationId,
                originNodeId: op.originNodeId,
                entityId: op.entityId,
                timestamp: op.timestamp,
                lamportClock: op.lamportClock,
                entityType: op.entityType,
                action: op.action,
                baseVersion: op.baseVersion,
                payload: .sos(coarsenedPayload)
            )
        }

        return op
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        trustedNodeIds.removeAll()
        peerPacketTimestamps.removeAll()
    }
}

