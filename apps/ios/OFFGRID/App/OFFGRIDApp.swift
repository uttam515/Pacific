import SwiftUI

@main
struct OFFGRIDApp: App {
    @StateObject private var transportManager = TransportManager()

    init() {
        // Initialize SQLite schema on launch
        _ = SQLiteDatabase.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transportManager)
                .onAppear {
                    transportManager.startAllTransports()
                }
        }
    }
}
