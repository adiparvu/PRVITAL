import Foundation

/// A stable, **non-identifying** per-install device tag for the audit trail.
///
/// Deliberately not the IDFV or any hardware identifier: a random UUID minted
/// once and kept in the shared container, so audit rows can be grouped by device
/// without the log itself becoming a tracking vector.
enum DeviceIdentity {
    private static let key = "com.diabetesjournal.deviceTag"

    static var current: String {
        let defaults = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        if let existing = defaults.string(forKey: key) { return existing }
        let tag = "dev-" + UUID().uuidString.prefix(8)
        defaults.set(String(tag), forKey: key)
        return String(tag)
    }
}
