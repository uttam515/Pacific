import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct RelayScoreBreakdown: Sendable, CustomStringConvertible {
    public let battery: Double      // B: 0 - 100
    public let reliability: Double  // Q: 0 - 100
    public let capacity: Double     // R: 0 - 100
    public let stability: Double    // C: 0 - 100
    public let totalScore: Double   // 0.35B + 0.30Q + 0.20R + 0.15C

    public init(battery: Double, reliability: Double, capacity: Double, stability: Double) {
        self.battery = max(0.0, min(100.0, battery))
        self.reliability = max(0.0, min(100.0, reliability))
        self.capacity = max(0.0, min(100.0, capacity))
        self.stability = max(0.0, min(100.0, stability))
        self.totalScore = (0.35 * self.battery) +
                          (0.30 * self.reliability) +
                          (0.20 * self.capacity) +
                          (0.15 * self.stability)
    }

    public var description: String {
        return String(format: "Score: %.1f (B=%.1f, Q=%.1f, R=%.1f, C=%.1f)",
                      totalScore, battery, reliability, capacity, stability)
    }
}

public struct PeerRoutingTelemetry: Sendable {
    public var successCount: Int = 0
    public var failureCount: Int = 0
    public var connectedSince: Date? = nil
    public var disconnectCount: Int = 0
    public var lastFailureTime: Date? = nil
    public var remoteBattery: Double? = nil

    public init() {}
}

/// Intelligent Routing Engine with real-metric deterministic relay scoring:
/// Score = 0.35B + 0.30Q + 0.20R + 0.15C
public final class RoutingEngine: @unchecked Sendable {
    public static let shared = RoutingEngine()

    private let lock = NSRecursiveLock()
    private var telemetryByPeer: [String: PeerRoutingTelemetry] = [:]
    private var pendingQueueBacklogProvider: (@Sendable () -> Int)?

    public init(backlogProvider: (@Sendable () -> Int)? = nil) {
        self.pendingQueueBacklogProvider = backlogProvider
    }

    public func setBacklogProvider(_ provider: @escaping @Sendable () -> Int) {
        lock.lock()
        defer { lock.unlock() }
        self.pendingQueueBacklogProvider = provider
    }

    // MARK: - Subscore Calculations

    /// B: Battery availability (0 - 100)
    /// Uses UIDevice monitoring if on iOS device, or documented fallback proxy
    public func calculateBatterySubscore(peerId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }

        // If peer provided remote battery telemetry via Bonjour TXT record or hello packet
        if let peerBattery = telemetryByPeer[peerId]?.remoteBattery {
            return peerBattery
        }

        #if canImport(UIKit) && !os(macOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if device.batteryState == .charging || device.batteryState == .full {
            return 100.0
        }
        let level = device.batteryLevel
        if level >= 0.0 {
            return Double(level * 100.0)
        }
        #endif

        // Documented fallback proxy: when battery level is unreadable (e.g. simulator, untracked remote peer)
        // Default to a healthy neutral baseline of 85.0
        return 85.0
    }

    /// Q: Connection reliability (0 - 100)
    /// Success ratio of delivered packets / total attempted transmissions
    public func calculateReliabilitySubscore(peerId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let telemetry = telemetryByPeer[peerId] else {
            // Newly discovered peer with no transmission history: neutral starting baseline of 80.0
            return 80.0
        }

        let total = telemetry.successCount + telemetry.failureCount
        guard total > 0 else {
            return 80.0
        }

        var ratio = (Double(telemetry.successCount) / Double(total)) * 100.0

        // Penalty if peer failed recently within the last 15 seconds (backoff avoidance)
        if let lastFail = telemetry.lastFailureTime, Date().timeIntervalSince(lastFail) < 15.0 {
            ratio = max(10.0, ratio - 30.0)
        }

        return ratio
    }

    /// R: Available forwarding capacity (0 - 100)
    /// Degrades inversely with local queue backlog to prevent congestion
    public func calculateCapacitySubscore() -> Double {
        lock.lock()
        let backlog = pendingQueueBacklogProvider?() ?? 0
        lock.unlock()

        // 0 backlog -> 100 capacity; each queued item reduces capacity by 5
        let capacity = 100.0 - Double(backlog * 5)
        return max(10.0, min(100.0, capacity))
    }

    /// C: Connection stability (0 - 100)
    /// Evaluated from active connection duration and low disconnect history
    public func calculateStabilitySubscore(peerId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let telemetry = telemetryByPeer[peerId], let connectedAt = telemetry.connectedSince else {
            return 50.0 // Default baseline for just-connecting peer
        }

        let durationSeconds = Date().timeIntervalSince(connectedAt)
        // Reaches max duration bonus at 5 minutes uptime (300s)
        let uptimeScore = min(50.0, (durationSeconds / 300.0) * 50.0)
        // Disconnect penalties
        let disconnectPenalty = Double(telemetry.disconnectCount * 15)
        let baseScore = max(0.0, 50.0 - disconnectPenalty)

        return min(100.0, baseScore + uptimeScore)
    }

    // MARK: - Relay Scoring

    /// Computes full relay score breakdown for a peer
    public func calculateRelayScore(for peer: DiscoveredPeer) -> RelayScoreBreakdown {
        let b = calculateBatterySubscore(peerId: peer.id)
        let q = calculateReliabilitySubscore(peerId: peer.id)
        let r = calculateCapacitySubscore()
        let c = calculateStabilitySubscore(peerId: peer.id)

        return RelayScoreBreakdown(battery: b, reliability: q, capacity: r, stability: c)
    }

    /// Ranks all available connected peers in descending order of relay score
    public func rankAvailablePeers(
        peers: [DiscoveredPeer],
        excluding: Set<String> = []
    ) -> [(peer: DiscoveredPeer, score: RelayScoreBreakdown)] {
        let eligible = peers.filter { $0.isConnected && !excluding.contains($0.id) && !excluding.contains($0.displayName) }

        let scored = eligible.map { peer in
            (peer: peer, score: calculateRelayScore(for: peer))
        }

        return scored.sorted { left, right in
            if left.score.totalScore != right.score.totalScore {
                return left.score.totalScore > right.score.totalScore
            }
            // Deterministic tie-breaker: compare display names lexicographically
            return left.peer.displayName.compare(right.peer.displayName) == .orderedDescending
        }
    }

    /// Selects the best next-hop relay candidate for an envelope
    public func selectNextHop(
        for envelope: ContractV1.Envelope,
        among peers: [DiscoveredPeer],
        excluding: Set<String> = []
    ) -> DiscoveredPeer? {
        var excludeSet = excluding
        // Always exclude the source node to prevent ping-pong loops
        excludeSet.insert(envelope.sourceNodeId)

        // If the target destination is directly connected among available peers, route directly!
        if envelope.destinationNodeId != "*" {
            if let directPeer = peers.first(where: {
                $0.isConnected &&
                !excludeSet.contains($0.id) &&
                ($0.id.caseInsensitiveCompare(envelope.destinationNodeId) == .orderedSame ||
                 $0.displayName.caseInsensitiveCompare(envelope.destinationNodeId) == .orderedSame)
            }) {
                return directPeer
            }
        }

        // Rank remaining candidates by multi-metric relay score
        let ranked = rankAvailablePeers(peers: peers, excluding: excludeSet)
        return ranked.first?.peer
    }

    /// Finds an alternative route when a primary relay fails or disconnects
    public func findAlternativeRoute(
        for envelope: ContractV1.Envelope,
        among peers: [DiscoveredPeer],
        excluding: Set<String>
    ) -> DiscoveredPeer? {
        return selectNextHop(for: envelope, among: peers, excluding: excluding)
    }

    // MARK: - Telemetry Observation

    public func recordPeerConnected(peerId: String) {
        lock.lock()
        defer { lock.unlock() }
        var telemetry = telemetryByPeer[peerId] ?? PeerRoutingTelemetry()
        telemetry.connectedSince = Date()
        telemetryByPeer[peerId] = telemetry
    }

    public func recordPeerDisconnected(peerId: String) {
        lock.lock()
        defer { lock.unlock() }
        var telemetry = telemetryByPeer[peerId] ?? PeerRoutingTelemetry()
        telemetry.connectedSince = nil
        telemetry.disconnectCount += 1
        telemetryByPeer[peerId] = telemetry
    }

    public func recordDeliveryAttempt(peerId: String, success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var telemetry = telemetryByPeer[peerId] ?? PeerRoutingTelemetry()
        if success {
            telemetry.successCount += 1
        } else {
            telemetry.failureCount += 1
            telemetry.lastFailureTime = Date()
        }
        telemetryByPeer[peerId] = telemetry
    }

    public func setRemoteBattery(peerId: String, battery: Double) {
        lock.lock()
        defer { lock.unlock() }
        var telemetry = telemetryByPeer[peerId] ?? PeerRoutingTelemetry()
        telemetry.remoteBattery = battery
        telemetryByPeer[peerId] = telemetry
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        telemetryByPeer.removeAll()
    }
}
