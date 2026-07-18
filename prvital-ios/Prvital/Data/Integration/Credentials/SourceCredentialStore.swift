import Foundation
import Security

/// Login details for a credentialed source (Dexcom Share, LibreLinkUp). Passwords
/// never touch `UserDefaults` — they live only in the Keychain, so this struct is
/// held in memory transiently and persisted through `SourceCredentialStore`.
struct SourceCredentials: Codable, Equatable, Sendable {
    var username: String
    var password: String
    /// Data region, e.g. Dexcom "us"/"ous". Empty when the source auto-detects.
    var region: String = ""

    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }
}

/// Stores `SourceCredentials` in the Keychain, keyed by data source. A generic
/// password item with `kSecAttrService` = the bundle prefix and `kSecAttrAccount`
/// = the source's raw value, protected until first unlock.
///
/// It is `nonisolated`/`Sendable`: every method is a synchronous Keychain call
/// with no shared mutable state, so sources can read credentials from any
/// isolation domain.
struct SourceCredentialStore: Sendable {
    static let shared = SourceCredentialStore()

    private let service = "com.prvital.credentials"

    func save(_ credentials: SourceCredentials, for source: DataSource) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let account = source.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func read(for source: DataSource) -> SourceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: source.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let credentials = try? JSONDecoder().decode(SourceCredentials.self, from: data)
        else { return nil }
        return credentials
    }

    func delete(for source: DataSource) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: source.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasCredentials(for source: DataSource) -> Bool {
        read(for: source)?.isComplete ?? false
    }
}
