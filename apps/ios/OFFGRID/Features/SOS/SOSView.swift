import SwiftUI

public struct SOSView: View {
    @StateObject private var viewModel = SOSViewModel()
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Emergency Classification")) {
                    Picker("Type", selection: $viewModel.selectedEmergencyType) {
                        ForEach(viewModel.emergencyTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Situation Details")) {
                    TextField("Describe immediate needs or coordinates...", text: $viewModel.emergencyDetails, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
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

                if let message = viewModel.broadcastSuccessMessage {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Emergency SOS")
            .onAppear {
                viewModel.configureTransport(transportManager)
            }
        }
    }
}
