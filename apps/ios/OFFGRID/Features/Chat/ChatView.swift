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
                        Text("Messages are saved to SQLite immediately and broadcast over local mesh.")
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
                                    MessageBubble(message: message)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text(message.status.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                Text(message.content)
                    .font(.body)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}
