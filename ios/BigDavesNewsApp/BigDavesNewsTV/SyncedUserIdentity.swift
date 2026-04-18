import Foundation
import Security

/// Anonymous accountless id (Keychain). Pass as `device_id` / `user_id` to Big Daves News APIs.
enum SyncedUserIdentity {
    private static let service = "com.bigdavesnews.sync.user"
    private static let account = "default"
    private static let legacyDefaultsKey = "bdn-watch-device-id"
    private static let defaultsMirrorKey = "bdn-sync-user-id-mirror"

    static var apiUserKey: String {
        if let kc = readKeychain(), !kc.isEmpty { return kc }
        if let defs = UserDefaults.standard.string(forKey: legacyDefaultsKey), !defs.isEmpty {
            _ = writeKeychain(defs)
            UserDefaults.standard.set(defs, forKey: defaultsMirrorKey)
            return defs
        }
        let fresh = UUID().uuidString.lowercased()
        _ = writeKeychain(fresh)
        UserDefaults.standard.set(fresh, forKey: defaultsMirrorKey)
        return fresh
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else {
            return nil
        }
        return s
    }

    @discardableResult
    private static func writeKeychain(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
