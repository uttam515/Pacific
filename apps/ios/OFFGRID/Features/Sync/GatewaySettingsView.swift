import SwiftUI

public struct GatewaySettingsView: View {
    @EnvironmentObject var gateway:GatewayManager
    @EnvironmentObject var transport:TransportManager
    @State private var url=""
    @State private var credential=""
    @State private var localHTTP=false
    @State private var error=""
    public var body: some View {
        Form {
            Section("Existing installation identity") {
                Text(transport.localNodeId).font(.caption.monospaced()).textSelection(.enabled)
                Text("Provision this exact ID as a gateway. Configuration never replaces it.").font(.caption)
            }
            Section("Private backend configuration") {
                TextField("https://backend.example",text:$url).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Privately provisioned bearer credential",text:$credential).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Allow HTTP on trusted local network",isOn:$localHTTP)
                Button("Save credential on this device") {
                    do {try gateway.configure(baseURL:url.trimmingCharacters(in:.whitespacesAndNewlines),credential:credential.trimmingCharacters(in:.whitespacesAndNewlines),allowLocalHTTP:localHTTP);credential="";error="";Task{await gateway.sync()}}
                    catch {error="Invalid URL, credential, or secure-storage failure. Use the existing installation ID when provisioning."}
                }
                if !error.isEmpty {Text(error).foregroundColor(.red)}
            }
            Section("SOS upload queue") {
                Text(gateway.status)
                LabeledContent("Pending",value:String(gateway.pendingCount))
                LabeledContent("Needs review",value:String(gateway.failedCount))
                LabeledContent("Backend committed",value:String(gateway.committedCount))
                Button("Check backend and retry due uploads"){Task{await gateway.sync()}}
                Button("Retry blocked uploads after correcting configuration"){gateway.retryBlocked();Task{await gateway.sync()}}
                Text("Peer receipt is separate from backend commitment. Uploads run while OFFGRID is active; iOS can suspend the app in the background. Keep gateway C open during physical testing.").font(.caption)
            }
        }.navigationTitle("Internet gateway")
    }
}
