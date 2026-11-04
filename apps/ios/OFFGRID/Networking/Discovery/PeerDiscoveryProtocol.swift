import Foundation
import Combine

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

public enum DiagnosticCategory: String, Sendable, CaseIterable {
    case discovery = "DISCOVERY"
    case invite = "INVITE"
    case session = "SESSION"
    case tx = "TX"
    case rx = "RX"
    case ack = "ACK"
    case error = "ERROR"
    case system = "SYSTEM"
}

public struct NetworkDiagnosticEntry: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let category: DiagnosticCategory
    public let message: String

    public init(category: DiagnosticCategory, message: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.category = category
        self.message = message
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    public var formattedLine: String {
        "[\(formattedTimestamp)] [\(category.rawValue)] \(message)"
    }
}

public final class NetworkDiagnosticLogger: ObservableObject, @unchecked Sendable {
    public static let shared = NetworkDiagnosticLogger()

    @Published public private(set) var entries: [NetworkDiagnosticEntry] = []
    private let maxEntries = 200

    public init() {}

    public func log(_ category: DiagnosticCategory, _ message: String) {
        let entry = NetworkDiagnosticEntry(category: category, message: message)
        print(entry.formattedLine)
        Task { @MainActor in
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    @MainActor
    public func clear() {
        entries.removeAll()
    }
}
