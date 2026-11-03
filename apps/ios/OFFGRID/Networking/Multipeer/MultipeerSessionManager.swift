import Foundation
import MultipeerConnectivity

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
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public weak var delegate: PeerDiscoveryDelegate?

    public private(set) var isAdvertising: Bool = false
    public private(set) var isBrowsing: Bool = false
    public private(set) var discoveredPeersList: [MCPeerID] = []
    public private(set) var connectedPeersList: [MCPeerID] = []

    public var onDiagnosticLog: ((DiagnosticCategory, String) -> Void)?

    public var hasConnectedPeers: Bool {
        return !(session?.connectedPeers.isEmpty ?? true)
    }

    public var connectedPeerNames: [String] {
        return session?.connectedPeers.map(\.displayName) ?? []
    }

    public init(displayName: String) {
        self.myPeerId = MCPeerID(displayName: displayName)
        super.init()
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        self.session?.delegate = self
    }

    public func start() {
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
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        isAdvertising = false
        isBrowsing = false
        discoveredPeersList.removeAll()
        connectedPeersList.removeAll()
        onDiagnosticLog?(.system, "Multipeer transport stopped")
    }

    @discardableResult
    public func broadcast(data: Data) -> Result<Int, Error> {
        guard let session = session else {
            return .failure(MultipeerError.sessionUnavailable)
        }
        guard !session.connectedPeers.isEmpty else {
            return .failure(MultipeerError.noConnectedPeers)
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            onDiagnosticLog?(.tx, "Sent \(data.count) bytes reliably to \(session.connectedPeers.count) peer(s)")
            return .success(session.connectedPeers.count)
        } catch {
            onDiagnosticLog?(.error, "Multipeer broadcast failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerSessionManager: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            if !connectedPeersList.contains(peerID) {
                connectedPeersList.append(peerID)
            }
            onDiagnosticLog?(.session, "Peer [\(peerID.displayName)] CONNECTED")
            let peer = DiscoveredPeer(
                id: peerID.displayName,
                displayName: peerID.displayName,
                transportType: .multipeer,
                isConnected: true
            )
            delegate?.didDiscoverPeer(peer)

        case .connecting:
            onDiagnosticLog?(.session, "Connecting to [\(peerID.displayName)]...")

        case .notConnected:
            connectedPeersList.removeAll { $0 == peerID }
            onDiagnosticLog?(.session, "Peer [\(peerID.displayName)] DISCONNECTED")
            delegate?.didLosePeer(peerID.displayName)

        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onDiagnosticLog?(.rx, "Received \(data.count) bytes from [\(peerID.displayName)]")
        delegate?.didReceivePacketData(data, from: peerID.displayName, transport: .multipeer)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        onDiagnosticLog?(.invite, "Received invitation from [\(peerID.displayName)], auto-accepting session")
        invitationHandler(true, self.session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        isAdvertising = false
        onDiagnosticLog?(.error, "Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if !discoveredPeersList.contains(peerID) {
            discoveredPeersList.append(peerID)
        }
        onDiagnosticLog?(.discovery, "Discovered nearby peer: [\(peerID.displayName)]")

        let discovered = DiscoveredPeer(
            id: peerID.displayName,
            displayName: peerID.displayName,
            transportType: .multipeer,
            isConnected: false
        )
        delegate?.didDiscoverPeer(discovered)

        guard let session = self.session else { return }

        // Deterministic Tie-Breaker:
        // When two devices discover each other, both sending invitations causes collision & disconnects.
        // We compare displayNames lexicographically: the peer with greater displayName sends invitation.
        // The peer with lesser displayName defers and auto-accepts the incoming invitation.
        if myPeerId.displayName.compare(peerID.displayName) == .orderedDescending {
            onDiagnosticLog?(.invite, "Sending session invitation to [\(peerID.displayName)] (tie-breaker won)")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        } else {
            onDiagnosticLog?(.invite, "Awaiting invitation from [\(peerID.displayName)] (tie-breaker deferred)")
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        discoveredPeersList.removeAll { $0 == peerID }
        onDiagnosticLog?(.discovery, "Lost contact with peer: [\(peerID.displayName)]")
        delegate?.didLosePeer(peerID.displayName)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        isBrowsing = false
        onDiagnosticLog?(.error, "Failed to start browsing: \(error.localizedDescription)")
    }
}
