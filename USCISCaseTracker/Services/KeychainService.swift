import Foundation
import Security

/// Secure storage for USCIS API credentials.
enum KeychainService {
    private static let service = "com.uscis-tracker.api"
    private static let clientIdKey = "uscis_client_id"
    private static let clientSecretKey = "uscis_client_secret"
    private static let useProductionKey = "uscis_use_production"

    static var clientId: String? {
        get { read(key: clientIdKey) }
        set { write(key: clientIdKey, value: newValue) }
    }

    static var clientSecret: String? {
        get { read(key: clientSecretKey) }
        set { write(key: clientSecretKey, value: newValue) }
    }

    static var hasCredentials: Bool {
        clientId.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } == true
            && clientSecret.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } == true
    }

    static var useProduction: Bool {
        get { read(key: useProductionKey) == "1" }
        set { write(key: useProductionKey, value: newValue ? "1" : nil) }
    }

    static func clearCredentials() {
        clientId = nil
        clientSecret = nil
    }

    private static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func write(key: String, value: String?) {
        delete(key: key)
        guard let value = value, !value.isEmpty else { return }
        guard let data = value.data(using: .utf8) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        #if os(macOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        #endif
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
