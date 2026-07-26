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
    /// Keychain access group shared with the widget extension, so the widget can
    /// fetch a fresh reading by itself when the app hasn't run. The prefix is the
    /// team identifier — it must match `$(AppIdentifierPrefix)` in the
    /// entitlements. On builds signed by a different team (or unsigned CI runs)
    /// every group operation fails with `errSecMissingEntitlement`, and the code
    /// below falls back to the app-local item, exactly the pre-group behaviour.
    private let sharedGroup = "SU92TVZT8W.com.prvital.shared"

    func save(_ credentials: SourceCredentials, for source: DataSource) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let account = source.rawValue

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: sharedGroup,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Moving into the shared group: clear any pre-group copy first so a
            // stale duplicate can't shadow the fresh item on group-less reads.
            var legacy = query
            legacy.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemDelete(legacy as CFDictionary)

            var insert = query
            insert.merge(attributes) { _, new in new }
            if SecItemAdd(insert as CFDictionary, nil) == errSecMissingEntitlement {
                insert.removeValue(forKey: kSecAttrAccessGroup as String)
                SecItemAdd(insert as CFDictionary, nil)
            }
        default:
            // No group entitlement (unsigned/dev build): keep the original
            // app-local upsert rather than dropping the credentials.
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            let local = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if local == errSecItemNotFound {
                var insert = query
                insert.merge(attributes) { _, new in new }
                SecItemAdd(insert as CFDictionary, nil)
            }
        }
    }

    /// Re-saves every stored credential so it lands in the shared access group.
    /// Called once at app bootstrap; a no-op after everything has moved (the
    /// group-qualified update in `save` then succeeds immediately).
    func migrateToSharedGroup() {
        for source in DataSource.allCases {
            if let credentials = read(for: source), credentials.isComplete {
                save(credentials, for: source)
            }
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
