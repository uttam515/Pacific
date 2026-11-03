import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var transportManager: TransportManager

    public init() {}

    public var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }

            SOSView()
                .tabItem {
                    Label("SOS", systemImage: "exclamationmark.triangle.fill")
                }

            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }

            NetworkStatusView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }

            SyncHistoryView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
    }
}
