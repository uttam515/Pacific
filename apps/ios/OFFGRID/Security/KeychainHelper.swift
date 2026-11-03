import Foundation
import Security

public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let serviceName = "org.offgrid.security"

    public func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
            return item as? Data
        }
        return nil
    }

    public func getOrCreateNodeId() -> String {
        let key = "offgrid_node_id"
        if let data = read(key: key), let existingId = String(data: data, encoding: .utf8) {
            return existingId
        }
        let newId = UUID().uuidString
        if let data = newId.data(using: .utf8) {
            _ = save(key: key, data: data)
        }
        return newId
    }
}
