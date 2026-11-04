import SwiftUI

@main
struct OFFGRIDApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var transportManager = TransportManager()

    init() {
        // Initialize SQLite schema on launch
        _ = SQLiteDatabase.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transportManager)
                .environmentObject(transportManager.gatewayManager)
                .onChange(of:scenePhase) { phase in
                    if phase == .active {transportManager.gatewayManager.start()}
                    else {transportManager.gatewayManager.stop()}
                }
                .onAppear {
                    transportManager.startAllTransports()
                }
        }
    }
}
