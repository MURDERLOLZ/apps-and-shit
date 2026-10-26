import Foundation
import Security

enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.r9k.swiftcord",
        kSecAttrAccount as String: "discord-token",
    ]

    static func save(_ token: String) -> Bool {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        // Never syncs to iCloud, never restores onto another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
