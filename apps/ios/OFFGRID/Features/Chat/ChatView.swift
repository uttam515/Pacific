import SwiftUI

public struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack {
                if viewModel.messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Offline Messages")
                            .font(.headline)
                        Text("Messages are committed to SQLite locally before radio transmission.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message) {
                                        viewModel.retryTransmission(for: message.id)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }

                // Input Bar
                HStack(spacing: 12) {
                    TextField("Write offline message...", text: $viewModel.inputMessage)
                        .textFieldStyle(.roundedBorder)

                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(viewModel.inputMessage.isEmpty ? .secondary : .accentColor)
                    }
                    .disabled(viewModel.inputMessage.isEmpty)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Offline Chat")
            .onAppear {
                viewModel.configureTransport(transportManager)
                viewModel.loadMessages()
            }
        }
    }
}

struct MessageBubble: View {
    let message: OFFGRIDMessage
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.senderName)
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                Spacer()
                DeliveryStatusBadge(status: message.status, onRetry: onRetry)
            }
            Text(message.content)
                .font(.body)

            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct DeliveryStatusBadge: View {
    let status: MessageDeliveryStatus
    let onRetry: () -> Void

    var body: some View {
        Button(action: {
            if status == .localOnly || status == .queued || status == .failed {
                onRetry()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2)
                Text(label)
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch status {
        case .localOnly: return "Local Only"
        case .queued: return "Queued"
        case .pending: return "Pending"
        case .relayed: return "Relayed"
        case .delivered: return "Delivered"
        case .synced: return "Synchronized"
        case .failed: return "Failed (Tap)"
        case .draft: return "Draft"
        }
    }

    private var iconName: String {
        switch status {
        case .localOnly: return "internaldrive"
        case .queued: return "clock.arrow.circlepath"
        case .pending: return "clock"
        case .relayed: return "antenna.radiowaves.left.and.right"
        case .delivered: return "checkmark.circle.fill"
        case .synced: return "cloud.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .draft: return "pencil"
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .localOnly: return Color.gray.opacity(0.15)
        case .queued: return Color.orange.opacity(0.15)
        case .pending: return Color.orange.opacity(0.15)
        case .relayed: return Color.blue.opacity(0.15)
        case .delivered: return Color.green.opacity(0.15)
        case .synced: return Color.purple.opacity(0.15)
        case .failed: return Color.red.opacity(0.15)
        case .draft: return Color.secondary.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .localOnly: return .secondary
        case .queued: return .orange
        case .pending: return .orange
        case .relayed: return .blue
        case .delivered: return .green
        case .synced: return .purple
        case .failed: return .red
        case .draft: return .secondary
        }
    }
}
