import Foundation

/// The LibreLinkUp "worn sensor" side-channel: the API's graph payload names the
/// current sensor (serial + activation instant), and whichever process fetched it
/// — the app's sync or the widget's self-refresh — drops it here in the shared
/// App Group. The app's `SensorAutoTracker` imports a not-yet-seen serial as a
/// sensor session on its next pass.
enum LibreSensorSignal {
    private static let serialKey = "sensor.libre.sn"
    private static let activatedKey = "sensor.libre.activatedAt"
    private static let importedKey = "sensor.libre.importedSN"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroupIdentifier) ?? .standard
    }

    /// Called from any isolation whenever LibreLinkUp reports the worn sensor.
    /// Just persists; the main-actor importer consumes it later.
    static func report(serial: String, activatedAt: Date) {
        guard !serial.isEmpty, activatedAt.timeIntervalSince1970 > 0 else { return }
        defaults.set(serial, forKey: serialKey)
        defaults.set(activatedAt.timeIntervalSince1970, forKey: activatedKey)
    }

    /// The reported sensor that hasn't been imported yet, if any.
    static func pending() -> (serial: String, activatedAt: Date)? {
        guard let serial = defaults.string(forKey: serialKey), !serial.isEmpty,
              defaults.string(forKey: importedKey) != serial else { return nil }
        let epoch = defaults.double(forKey: activatedKey)
        guard epoch > 0 else { return nil }
        return (serial, Date(timeIntervalSince1970: epoch))
    }

    /// Marks a serial consumed, so an older report can never retry forever.
    static func markImported(serial: String) {
        defaults.set(serial, forKey: importedKey)
    }
}
