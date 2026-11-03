import Foundation
import MultipeerConnectivity

public final class MultipeerSessionManager: NSObject, @unchecked Sendable {
    public static let serviceType = "offgrid-mesh"

    private let myPeerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public weak var delegate: PeerDiscoveryDelegate?

    public init(displayName: String) {
        self.myPeerId = MCPeerID(displayName: displayName)
        super.init()
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        self.session?.delegate = self
    }

    public func start() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        print("[Multipeer] Started advertising and browsing with peer: \(myPeerId.displayName)")
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
    }

    public func broadcast(data: Data) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[Multipeer] Send error: \(error)")
        }
    }
}

extension MultipeerSessionManager: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let isConnected = (state == .connected)
        let peer = DiscoveredPeer(
            id: peerID.displayName,
            displayName: peerID.displayName,
            transportType: .multipeer,
            isConnected: isConnected
        )
        if state == .notConnected {
            delegate?.didLosePeer(peerID.displayName)
        } else {
            delegate?.didDiscoverPeer(peer)
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        delegate?.didReceivePacketData(data, from: peerID.displayName, transport: .multipeer)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from OFFGRID peers
        invitationHandler(true, self.session)
    }
}

extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let session = self.session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        delegate?.didLosePeer(peerID.displayName)
    }
}
