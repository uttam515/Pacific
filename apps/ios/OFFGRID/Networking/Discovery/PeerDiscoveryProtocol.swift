import Foundation

public enum TransportType: String, Sendable {
    case multipeer = "Multipeer"
    case bluetooth = "Bluetooth LE"
    case localNetwork = "Local IP"
    case cloudGateway = "Cloud Gateway"
}

public struct DiscoveredPeer: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let transportType: TransportType
    public let lastDiscovered: Date
    public var isConnected: Bool

    public init(id: String, displayName: String, transportType: TransportType, lastDiscovered: Date = Date(), isConnected: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.transportType = transportType
        self.lastDiscovered = lastDiscovered
        self.isConnected = isConnected
    }
}

public protocol PeerDiscoveryDelegate: AnyObject, Sendable {
    func didDiscoverPeer(_ peer: DiscoveredPeer)
    func didLosePeer(_ peerId: String)
    func didReceivePacketData(_ data: Data, from peerId: String, transport: TransportType)
}
