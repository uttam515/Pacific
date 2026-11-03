import SwiftUI

public struct FilesView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Announcements & Offline Files")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mesh Protocol v1 Specification")
                            .font(.headline)
                        Text("Shared from Central Infrastructure • Size: 24 KB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emergency Evacuation Map")
                            .font(.headline)
                        Text("Cached locally for offline guidance • Size: 180 KB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Offline File Distribution")) {
                    Text("Store-and-forward chunking protocol will synchronize large files across intermediate mesh hops.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Files & Announcements")
        }
    }
}
