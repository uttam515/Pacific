import SwiftUI

public struct HomeDashboardView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Status Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("OFFGRID Core")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Mesh Status: ACTIVE")
                                    .font(.title2.bold())
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                        }

                        Divider()

                        HStack(spacing: 20) {
                            StatusMetric(title: "Active Peers", value: "\(transportManager.activePeers.count)", icon: "person.2.fill")
                            StatusMetric(title: "Pending Sync", value: "\(viewModel.pendingSyncCount)", icon: "arrow.triangle.2.circlepath")
                            StatusMetric(title: "Gateway", value: transportManager.isGatewayConnected ? "ONLINE" : "OFFLINE", icon: "cloud.fill")
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    // Quick Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Emergency Protocol")
                            .font(.headline)

                        NavigationLink(destination: SOSView()) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                VStack(alignment: .leading) {
                                    Text("Broadcast Emergency SOS")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Immediate high-priority peer broadcast")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                    }

                    // System Architecture Information
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Architecture Demarcation")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            DemarcationRow(role: "Engineer 1", title: "Backend, Web & Protocol Lead", status: "Contracts Ready")
                            DemarcationRow(role: "Engineer 2", title: "Native Android App", status: "BLE Interop Ready")
                            DemarcationRow(role: "Engineer 3 (Me)", title: "Native iOS App & SQLite", status: "Scaffold Verified")
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("OFFGRID Hub")
            .onAppear {
                viewModel.loadDashboardStats()
            }
        }
    }
}

struct StatusMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DemarcationRow: View {
    let role: String
    let title: String
    let status: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(role)
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline)
            }
            Spacer()
            Text(status)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(6)
        }
    }
}
