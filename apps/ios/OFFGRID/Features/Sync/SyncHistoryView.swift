import SwiftUI

public struct SyncHistoryView: View {
    @StateObject private var viewModel = SyncViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Offline Operation Queue")) {
                    if viewModel.pendingOperations.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All local operations are synchronized")
                                .font(.subheadline)
                        }
                    } else {
                        ForEach(viewModel.pendingOperations) { op in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(op.action.rawValue) \(op.entityType.rawValue)")
                                        .font(.headline)
                                    Spacer()
                                    Text(op.syncStatus.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                                Text("Clock: \(op.lamportClock) • ID: \(op.id.prefix(8))...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    Button(action: {
                        viewModel.triggerManualSync()
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isSyncing {
                                ProgressView()
                            } else {
                                Text("Sync Now with Gateway")
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Sync History")
            .onAppear {
                viewModel.loadOperations()
            }
        }
    }
}
