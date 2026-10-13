import Foundation
import Security
import SpeakWayCore

enum Keychain {
    private static func query(_ provider: CredentialProvider) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.speakway.mac", kSecAttrAccount as String: provider.rawValue] }
    static func read(_ provider: CredentialProvider) -> String {
        var request = query(provider); request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &data) == errSecSuccess, let data = data as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ key: String, for provider: CredentialProvider) throws {
        let query = query(provider)
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SpeakWayError.message("Could not remove the key from Keychain (\(status)).") }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var entry = query; entry[kSecValueData as String] = Data(value.utf8)
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(entry as CFDictionary, nil)
            guard status == errSecSuccess else { throw SpeakWayError.message("Could not save the key in Keychain (\(status)).") }
        } else if update != errSecSuccess { throw SpeakWayError.message("Could not update the key in Keychain (\(update)).") }
    }
}
