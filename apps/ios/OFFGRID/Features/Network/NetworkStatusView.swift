import SwiftUI

public struct NetworkStatusView: View {
    @StateObject private var viewModel = NetworkViewModel()
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Local Node Identity")) {
                    HStack {
                        Text("Node ID")
                        Spacer()
                        Text(String(viewModel.localNodeId.prefix(12)) + "...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Hardware")
                        Spacer()
                        Text("Apple iOS (ARM64)")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Active Mesh Radios")) {
                    HStack {
                        Label("Apple Multipeer Connectivity", systemImage: "wifi")
                        Spacer()
                        Text("Active")
                            .foregroundColor(.green)
                    }
                    HStack {
                        Label("CoreBluetooth LE (Android Bridge)", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Text("Active")
                            .foregroundColor(.green)
                    }
                }

                Section(header: Text("Discovered Peers (\(transportManager.activePeers.count))")) {
                    if transportManager.activePeers.isEmpty {
                        Text("Searching for nearby OFFGRID devices...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(transportManager.activePeers) { peer in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(peer.displayName)
                                        .font(.headline)
                                    Text("Via \(peer.transportType.rawValue)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(peer.isConnected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Network Status")
        }
    }
}
