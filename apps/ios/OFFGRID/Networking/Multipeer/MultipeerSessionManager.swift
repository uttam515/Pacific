import Foundation
import MultipeerConnectivity
import Security

public enum MultipeerError: Error, LocalizedError {
    case noConnectedPeers
    case sessionUnavailable

    public var errorDescription: String? {
        switch self {
        case .noConnectedPeers: return "No connected multipeer devices available"
        case .sessionUnavailable: return "Multipeer session is uninitialized"
        }
    }
}

public final class MultipeerSessionManager: NSObject, @unchecked Sendable {
    public static let serviceType = "offgrid-mesh"

    public let myPeerId: MCPeerID
    private let lock = NSRecursiveLock()

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public weak var delegate: PeerDiscoveryDelegate?

    public private(set) var isAdvertising: Bool = false
    public private(set) var isBrowsing: Bool = false
    public private(set) var discoveredPeersList: [MCPeerID] = []
    public private(set) var connectedPeersList: [MCPeerID] = []

    private var reconnectWorkItems: [String: DispatchWorkItem] = [:]

    public var onDiagnosticLog: ((DiagnosticCategory, String) -> Void)?

    /// When true, enables development auto-approval mode for local test mesh and physical debugging.
    /// When false, requires strict SecTrust X.509 verification or explicit certificateValidator approval.
    public var allowDevelopmentCertificates: Bool = true

    /// Optional explicit validator closure for custom trust pinning, pairing tokens, or authorized node IDs.
    public var certificateValidator: (@Sendable (MCPeerID, [Any]?) -> Bool)?

    public var hasConnectedPeers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !(session?.connectedPeers.isEmpty ?? true)
    }

    public var connectedPeerNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return session?.connectedPeers.map(\.displayName) ?? []
    }

    public func getConnectedPeerObjects() -> [DiscoveredPeer] {
        lock.lock()
        defer { lock.unlock() }
        guard let peers = session?.connectedPeers else { return [] }
        return peers.map {
            DiscoveredPeer(id: $0.displayName, displayName: $0.displayName, transportType: .multipeer, isConnected: true)
        }
    }

    public init(displayName: String) {
        self.myPeerId = MCPeerID(displayName: displayName)
        super.init()
        self.session = createNewSession()
    }

    private func createNewSession() -> MCSession {
        let newSession = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        newSession.delegate = self
        return newSession
    }

    public func getOrCreateSession() -> MCSession {
        lock.lock()
        defer { lock.unlock() }
        if let existing = session {
            return existing
        }
        let newSession = createNewSession()
        self.session = newSession
        return newSession
    }

    public func resetSessionIfEmpty() {
        lock.lock()
        defer { lock.unlock() }
        if let current = session, current.connectedPeers.isEmpty {
            current.disconnect()
            current.delegate = nil
            self.session = createNewSession()
            onDiagnosticLog?(.session, "Refreshed MCSession for clean reconnection")
        }
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        if session == nil {
            session = createNewSession()
        }

        if advertiser == nil {
            advertiser = MCNearbyServiceAdvertiser(
                peer: myPeerId,
                discoveryInfo: ["nodeId": myPeerId.displayName],
                serviceType: Self.serviceType
            )
            advertiser?.delegate = self
        }
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        onDiagnosticLog?(.discovery, "Started advertising Bonjour service '\(Self.serviceType)' as '\(myPeerId.displayName)'")

        if browser == nil {
            browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
            browser?.delegate = self
        }
        browser?.startBrowsingForPeers()
        isBrowsing = true
        onDiagnosticLog?(.discovery, "Started browsing for Bonjour service '\(Self.serviceType)'")
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        session?.delegate = nil
        session = nil

        for item in reconnectWorkItems.values {
            item.cancel()
        }
        reconnectWorkItems.removeAll()

        isAdvertising = false
        isBrowsing = false
        discoveredPeersList.removeAll()
        connectedPeersList.removeAll()
        onDiagnosticLog?(.system, "Multipeer transport stopped")
    }

    @discardableResult
    public func broadcast(data: Data) -> Result<Int, Error> {
        return send(data: data, toPeers: nil)
    }

    @discardableResult
    public func send(data: Data, toPeers peerNames: [String]?) -> Result<Int, Error> {
        lock.lock()
        guard let session = session else {
            lock.unlock()
            return .failure(MultipeerError.sessionUnavailable)
        }
        let allPeers = session.connectedPeers
        let targetPeers: [MCPeerID]
        if let names = peerNames, !names.isEmpty {
            let matched = allPeers.filter { peer in
                names.contains(where: { name in
                    peer.displayName.caseInsensitiveCompare(name) == .orderedSame ||
                    name.lowercased().contains(peer.displayName.lowercased())
                })
            }
            targetPeers = matched.isEmpty ? allPeers : matched
        } else {
            targetPeers = allPeers
        }
        lock.unlock()

        guard !targetPeers.isEmpty else {
            return .failure(MultipeerError.noConnectedPeers)
        }

        do {
            try session.send(data, toPeers: targetPeers, with: .reliable)
            onDiagnosticLog?(.tx, "Sent \(data.count) bytes reliably to \(targetPeers.count) peer(s)")
            return .success(targetPeers.count)
        } catch {
            onDiagnosticLog?(.error, "Multipeer send failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func attemptConnection(to peerID: MCPeerID, reason: String) {
        lock.lock()
        let isConnected = connectedPeersList.contains(peerID)
        lock.unlock()

        guard !isConnected else { return }

        // Deterministic Tie-Breaker:
        // Devices compare displayNames lexicographically.
        // The peer with greater displayName sends session invitation.
        // The peer with lesser displayName defers and auto-accepts the incoming invitation.
        let comparison = myPeerId.displayName.compare(peerID.displayName)
        let shouldInvite: Bool
        if comparison == .orderedDescending {
            shouldInvite = true
        } else if comparison == .orderedSame {
            // Edge-case secondary tie-breaker if display names match
            shouldInvite = myPeerId.hashValue >= peerID.hashValue
        } else {
            shouldInvite = false
        }

        if shouldInvite {
            onDiagnosticLog?(.invite, "Sending session invitation to [\(peerID.displayName)] (tie-breaker won, \(reason))")
            let currentSession = getOrCreateSession()
            browser?.invitePeer(peerID, to: currentSession, withContext: nil, timeout: 15)
        } else {
            onDiagnosticLog?(.invite, "Awaiting invitation from [\(peerID.displayName)] (tie-breaker deferred, \(reason))")
        }
    }

    private func scheduleReconnect(to peerID: MCPeerID, delay: TimeInterval) {
        lock.lock()
        reconnectWorkItems[peerID.displayName]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let isDiscovered = self.discoveredPeersList.contains(peerID)
            let isConnected = self.connectedPeersList.contains(peerID)
            self.lock.unlock()

            guard isDiscovered && !isConnected else { return }

            self.onDiagnosticLog?(.session, "Initiating scheduled reconnect to [\(peerID.displayName)]...")
            self.resetSessionIfEmpty()
            self.attemptConnection(to: peerID, reason: "reconnect retry")
        }

        reconnectWorkItems[peerID.displayName] = workItem
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - MCSessionDelegate
extension MultipeerSessionManager: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            lock.lock()
            if !connectedPeersList.contains(peerID) {
                connectedPeersList.append(peerID)
            }
            reconnectWorkItems[peerID.displayName]?.cancel()
            reconnectWorkItems.removeValue(forKey: peerID.displayName)
            let totalConnected = connectedPeersList.count
            lock.unlock()

            onDiagnosticLog?(.session, "Peer [\(peerID.displayName)] CONNECTED (MCSessionState: connected, active: \(totalConnected))")
            let peer = DiscoveredPeer(
                id: peerID.displayName,
                displayName: peerID.displayName,
                transportType: .multipeer,
                isConnected: true
            )
            delegate?.didDiscoverPeer(peer)

        case .connecting:
            onDiagnosticLog?(.session, "Connecting to [\(peerID.displayName)] (MCSessionState: connecting)...")

        case .notConnected:
            lock.lock()
            connectedPeersList.removeAll { $0 == peerID }
            let isStillDiscovered = discoveredPeersList.contains(peerID)
            lock.unlock()

            onDiagnosticLog?(.session, "Peer [\(peerID.displayName)] DISCONNECTED (MCSessionState: notConnected)")

            if isStillDiscovered {
                // Peer remains discovered via Bonjour browser; mark as disconnected but do NOT purge from activePeers
                let peer = DiscoveredPeer(
                    id: peerID.displayName,
                    displayName: peerID.displayName,
                    transportType: .multipeer,
                    isConnected: false
                )
                delegate?.didDiscoverPeer(peer)

                // If this node is the tie-breaker winner, schedule a retry with a refreshed clean session
                let comparison = myPeerId.displayName.compare(peerID.displayName)
                let shouldRetry = (comparison == .orderedDescending) || (comparison == .orderedSame && myPeerId.hashValue >= peerID.hashValue)
                if shouldRetry {
                    scheduleReconnect(to: peerID, delay: 2.0)
                } else {
                    // Receiver / tie-breaker loser: refresh empty session so incoming invite hits a clean state
                    resetSessionIfEmpty()
                }
            } else {
                delegate?.didLosePeer(peerID.displayName)
            }

        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onDiagnosticLog?(.rx, "Received \(data.count) bytes from [\(peerID.displayName)]")
        delegate?.didReceivePacketData(data, from: peerID.displayName, transport: .multipeer)
    }

    public func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        if let validator = certificateValidator {
            let approved = validator(peerID, certificate)
            onDiagnosticLog?(.session, "Validating peer certificate from [\(peerID.displayName)] via custom validator -> \(approved ? "APPROVED" : "REJECTED")")
            certificateHandler(approved)
            return
        }

        if allowDevelopmentCertificates {
            onDiagnosticLog?(.session, "Validating peer certificate from [\(peerID.displayName)] -> APPROVED (development auto-approval mode)")
            certificateHandler(true)
            return
        }

        // Production verification: evaluate SecTrust against system/pinned certificates
        guard let certs = certificate as? [SecCertificate], let firstCert = certs.first else {
            onDiagnosticLog?(.error, "Rejecting peer [\(peerID.displayName)]: missing or invalid certificate chain")
            certificateHandler(false)
            return
        }

        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(firstCert, policy, &trust)
        guard status == errSecSuccess, let secTrust = trust else {
            onDiagnosticLog?(.error, "Rejecting peer [\(peerID.displayName)]: failed to create SecTrust object")
            certificateHandler(false)
            return
        }

        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(secTrust, &error)
        onDiagnosticLog?(.session, "Production SecTrust evaluation for [\(peerID.displayName)] -> \(isTrusted ? "APPROVED" : "REJECTED (\(error?.localizedDescription ?? "untrusted"))")")
        certificateHandler(isTrusted)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        onDiagnosticLog?(.invite, "Received invitation from [\(peerID.displayName)], auto-accepting into MCSession")
        let sessionToUse = getOrCreateSession()
        invitationHandler(true, sessionToUse)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        lock.lock()
        isAdvertising = false
        lock.unlock()
        onDiagnosticLog?(.error, "Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        lock.lock()
        if !discoveredPeersList.contains(peerID) {
            discoveredPeersList.append(peerID)
        }
        lock.unlock()

        onDiagnosticLog?(.discovery, "Discovered nearby peer: [\(peerID.displayName)]")

        let discovered = DiscoveredPeer(
            id: peerID.displayName,
            displayName: peerID.displayName,
            transportType: .multipeer,
            isConnected: false
        )
        delegate?.didDiscoverPeer(discovered)

        attemptConnection(to: peerID, reason: "initial discovery")
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.lock()
        discoveredPeersList.removeAll { $0 == peerID }
        connectedPeersList.removeAll { $0 == peerID }
        reconnectWorkItems[peerID.displayName]?.cancel()
        reconnectWorkItems.removeValue(forKey: peerID.displayName)
        lock.unlock()

        onDiagnosticLog?(.discovery, "Lost contact with peer: [\(peerID.displayName)]")
        delegate?.didLosePeer(peerID.displayName)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        lock.lock()
        isBrowsing = false
        lock.unlock()
        onDiagnosticLog?(.error, "Failed to start browsing: \(error.localizedDescription)")
    }
}
