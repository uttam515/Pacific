import Foundation

public final class InstallationIdentityManager: @unchecked Sendable {
    public static let shared = InstallationIdentityManager()
    
    private let markerFileName = "installation_marker.json"
    private let keychainKey = "offgrid_node_id"
    private let lock = NSLock()
    private var cachedNodeId: String?
    private let customStorageDirectory: URL?
    
    public struct InstallationMarker: Codable {
        public let nodeId: String
        public let installedAt: Int64
        public let schemaVersion: Int
        
        public init(nodeId: String, installedAt: Int64, schemaVersion: Int = 1) {
            self.nodeId = nodeId
            self.installedAt = installedAt
            self.schemaVersion = schemaVersion
        }
    }
    
    public init(customStorageDirectory: URL? = nil) {
        self.customStorageDirectory = customStorageDirectory
    }
    
    public func getNodeId() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedNodeId {
            return cached
        }
        
        let markerURL = getMarkerFileURL()
        let fileManager = FileManager.default
        
        // Case 2: Marker file exists and is valid
        if fileManager.fileExists(atPath: markerURL.path),
           let data = try? Data(contentsOf: markerURL),
           let marker = try? JSONDecoder().decode(InstallationMarker.self, from: data),
           isValidLowercaseUUID(marker.nodeId) {
            self.cachedNodeId = marker.nodeId
            // Ensure Keychain is in sync
            if let markerData = marker.nodeId.data(using: .utf8) {
                _ = KeychainHelper.shared.save(key: keychainKey, data: markerData)
            }
            return marker.nodeId
        }

        // Case 3: Prototype adoption (marker file absent, but existing Keychain identity present)
        if let kcData = KeychainHelper.shared.read(key: keychainKey),
           let rawKcId = String(data: kcData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let uuid = UUID(uuidString: rawKcId) {
            let adoptedId = uuid.uuidString.lowercased()
            writeMarkerFile(nodeId: adoptedId, markerURL: markerURL)
            if let adoptedData = adoptedId.data(using: .utf8) {
                _ = KeychainHelper.shared.save(key: keychainKey, data: adoptedData)
            }
            self.cachedNodeId = adoptedId
            return adoptedId
        }
        
        // Case 1: Fresh install
        let newId = UUID().uuidString.lowercased()
        writeMarkerFile(nodeId: newId, markerURL: markerURL)
        if let data = newId.data(using: .utf8) {
            _ = KeychainHelper.shared.save(key: keychainKey, data: data)
        }
        self.cachedNodeId = newId
        return newId
    }
    
    public func getMarkerFileURL() -> URL {
        let fileManager = FileManager.default
        let appSupportDir: URL
        
        if let custom = customStorageDirectory {
            appSupportDir = custom
        } else if let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                  (try? fileManager.createDirectory(at: dir.appendingPathComponent("OFFGRID", isDirectory: true), withIntermediateDirectories: true, attributes: nil)) != nil {
            appSupportDir = dir.appendingPathComponent("OFFGRID", isDirectory: true)
        } else if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
                  (try? fileManager.createDirectory(at: docDir.appendingPathComponent("OFFGRID", isDirectory: true), withIntermediateDirectories: true, attributes: nil)) != nil {
            appSupportDir = docDir.appendingPathComponent("OFFGRID", isDirectory: true)
        } else {
            appSupportDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("OFFGRID", isDirectory: true)
        }
        
        if !fileManager.fileExists(atPath: appSupportDir.path) {
            try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
        }
        return appSupportDir.appendingPathComponent(markerFileName)
    }
    
    public func writeMarkerFile(nodeId: String, markerURL: URL) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let marker = InstallationMarker(nodeId: nodeId, installedAt: nowMs, schemaVersion: 1)
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: markerURL, options: .atomic)
            
            var url = markerURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }
    
    private func isValidLowercaseUUID(_ str: String) -> Bool {
        let pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        return str.range(of: pattern, options: .regularExpression) != nil
    }
}
