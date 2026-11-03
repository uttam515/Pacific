import SwiftUI

public struct SOSView: View {
    @StateObject private var viewModel = SOSViewModel()
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Active Received Emergency Beacons
                Section(header: Label("Active Emergency Beacons (\(viewModel.activeAlerts.count))", systemImage: "exclamationmark.triangle.fill")) {
                    if viewModel.activeAlerts.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .foregroundColor(.secondary)
                            Text("No active emergency beacons received from nearby peers.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.activeAlerts) { alert in
                            ReceivedSOSAlertRow(alert: alert)
                        }
                    }
                }

                // Section 2: Broadcast Emergency SOS Form
                Section(header: Text("Broadcast Emergency SOS")) {
                    Picker("Emergency Type", selection: $viewModel.selectedEmergencyType) {
                        ForEach(viewModel.emergencyTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Describe immediate needs, hazards, or coordinates...", text: $viewModel.emergencyDetails, axis: .vertical)
                        .lineLimit(3...6)

                    Button(action: {
                        viewModel.broadcastSOS()
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "exclamationmark.shield.fill")
                            Text("BROADCAST EMERGENCY SOS")
                                .bold()
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.red)
                }

                // Section 3: Outgoing SOS Status & Radio Confirmation
                if let status = viewModel.outgoingStatus, let message = viewModel.broadcastSuccessMessage {
                    Section(header: Text("Outgoing Beacon Status")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SOSStatusBadge(status: status)
                                Spacer()
                                Text(status == .delivered ? "PEER CONFIRMED" : "RADIO TRANSIT")
                                    .font(.caption2.bold())
                                    .foregroundColor(status == .delivered ? .green : .orange)
                            }

                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            if status == .queued || status == .failed || status == .localOnly {
                                Button(action: {
                                    if let first = viewModel.mySentSOS.first {
                                        viewModel.retryBroadcast(for: first.id)
                                    }
                                }) {
                                    Label("Retry Transmission Now", systemImage: "arrow.clockwise")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Section 4: Sent Beacons Log
                if !viewModel.mySentSOS.isEmpty {
                    Section(header: Text("My Outgoing Beacons (\(viewModel.mySentSOS.count))")) {
                        ForEach(viewModel.mySentSOS) { sent in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sent.content)
                                        .font(.subheadline.bold())
                                    Text(sent.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                SOSStatusBadge(status: sent.status)
                            }
                        }
                    }
                }

                // Section 5: Protocol Safety Notice
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Critical Operational Advisory", systemImage: "info.circle.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text("Peer delivery confirms radio packet receipt by a nearby OFFGRID node. It does NOT indicate that emergency rescue personnel or aid have arrived. Remain in a safe position and re-attempt broadcast if conditions change.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Emergency SOS")
            .onAppear {
                viewModel.configureTransport(transportManager)
                viewModel.loadSOSData()
            }
        }
    }
}

// MARK: - Subviews
struct ReceivedSOSAlertRow: View {
    let alert: OFFGRIDMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("EMERGENCY ALERT", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption.bold())
                    .foregroundColor(.red)
                Spacer()
                Text(alert.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(alert.content)
                .font(.body.bold())
                .foregroundColor(.red)

            Divider()

            HStack {
                Text("Origin: \(alert.senderName)")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("RECEIVED OVER MESH")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SOSStatusBadge: View {
    let status: MessageDeliveryStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }

    private var label: String {
        switch status {
        case .localOnly: return "Local SQLite Only"
        case .queued: return "Queued for Mesh"
        case .relayed: return "Relayed (In Transit)"
        case .delivered: return "Acknowledged by Peer"
        case .synced: return "Gateway Synced"
        case .failed: return "Transmission Failed"
        default: return status.rawValue
        }
    }

    private var color: Color {
        switch status {
        case .localOnly: return .gray
        case .queued: return .orange
        case .relayed: return .blue
        case .delivered: return .green
        case .synced: return .purple
        case .failed: return .red
        default: return .secondary
        }
    }
}
