import SwiftUI

public struct NetworkStatusView: View {
    @StateObject private var viewModel = NetworkViewModel()
    @EnvironmentObject var transportManager: TransportManager
    @ObservedObject private var logger = NetworkDiagnosticLogger.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Local Node Identity
                Section(header: Text("Local Node Identity")) {
                    HStack {
                        Label("Device Name", systemImage: "iphone")
                        Spacer()
                        Text(viewModel.localDeviceName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Node ID", systemImage: "key.fill")
                        Spacer()
                        Text(viewModel.localNodeId.prefix(12) + "...")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                        Button(action: {
                            UIPasteboard.general.string = viewModel.localNodeId
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Label("Hardware Platform", systemImage: "cpu")
                        Spacer()
                        Text("Apple iOS (ARM64)")
                            .foregroundColor(.secondary)
                    }
                }

                // Section 2: Mesh Radios & Session Status
                Section(header: Text("Mesh Radio Status")) {
                    HStack {
                        Label("Multipeer Advertising", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        StatusPill(
                            isActive: transportManager.isAdvertising,
                            activeText: "Advertising",
                            inactiveText: "Inactive"
                        )
                    }

                    HStack {
                        Label("Multipeer Browsing", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        StatusPill(
                            isActive: transportManager.isBrowsing,
                            activeText: "Browsing",
                            inactiveText: "Inactive"
                        )
                    }

                    HStack {
                        Label("CoreBluetooth LE", systemImage: "bolt.horizontal.fill")
                        Spacer()
                        StatusPill(
                            isActive: true,
                            activeText: "Ready",
                            inactiveText: "Inactive"
                        )
                    }

                    HStack {
                        Label("Session Status", systemImage: "network")
                        Spacer()
                        if !transportManager.connectedPeers.isEmpty {
                            Text("Connected (\(transportManager.connectedPeers.count))")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else if !transportManager.activePeers.isEmpty {
                            Text("Discovered (\(transportManager.activePeers.count))")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        } else {
                            Text("Searching...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let lastRx = transportManager.lastReceivedPacketTime {
                        HStack {
                            Label("Last Packet Rx", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text(lastRx.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section 3: Connected Peers
                Section(header: Text("Connected Peers (\(transportManager.connectedPeers.count))")) {
                    if transportManager.connectedPeers.isEmpty {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundColor(.secondary)
                            Text("No peers directly connected right now.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(transportManager.connectedPeers) { peer in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .font(.headline)
                                    Text("Connected via \(peer.transportType.rawValue)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("ONLINE")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Section 4: Discovered Peers Nearby
                Section(header: Text("Nearby Peers Discovered (\(transportManager.activePeers.count))")) {
                    if transportManager.activePeers.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                            Text("Scanning Wi-Fi / Bluetooth for OFFGRID nodes...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(transportManager.activePeers) { peer in
                            HStack {
                                Circle()
                                    .fill(peer.isConnected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .font(.subheadline)
                                    Text("Discovered \(peer.lastDiscovered.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(peer.isConnected ? "LINKED" : "UNLINKED")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((peer.isConnected ? Color.green : Color.orange).opacity(0.15))
                                    .foregroundColor(peer.isConnected ? .green : .orange)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Section 5: Diagnostic Console
                Section(
                    header: HStack {
                        Text("Live Diagnostic Console (\(logger.entries.count))")
                        Spacer()
                        Button("Clear") {
                            viewModel.clearLogs()
                        }
                        .font(.caption.bold())
                    }
                ) {
                    if logger.entries.isEmpty {
                        Text("No radio diagnostic events recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(logger.entries) { entry in
                                        DiagnosticLogRow(entry: entry)
                                            .id(entry.id)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(minHeight: 180, maxHeight: 280)
                        }
                    }

                    // Radio controls
                    HStack {
                        Button(action: {
                            transportManager.stopAllTransports()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                transportManager.startAllTransports()
                            }
                        }) {
                            Label("Restart Radios", systemImage: "arrow.clockwise")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: {
                            transportManager.flushPendingQueue()
                        }) {
                            Label("Flush Queue", systemImage: "paperplane.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Network Status")
        }
    }
}

// MARK: - Subviews
struct StatusPill: View {
    let isActive: Bool
    let activeText: String
    let inactiveText: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(isActive ? activeText : inactiveText)
                .font(.caption.bold())
                .foregroundColor(isActive ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isActive ? Color.green : Color.gray).opacity(0.12))
        .cornerRadius(6)
    }
}

struct DiagnosticLogRow: View {
    let entry: NetworkDiagnosticEntry

    var categoryColor: Color {
        switch entry.category {
        case .discovery: return .blue
        case .invite: return .purple
        case .session: return .cyan
        case .tx: return .green
        case .rx: return .indigo
        case .ack: return .mint
        case .error: return .red
        case .system: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.formattedTimestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            Text("[\(entry.category.rawValue)]")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(categoryColor)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(nil)
        }
    }
}
