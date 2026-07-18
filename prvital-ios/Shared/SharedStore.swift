import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Reads and writes the `GlucoseSnapshot` in the shared App Group container and
/// nudges WidgetKit to reload when it changes. This is the only bridge between
/// the app and its extensions.
enum SharedStore {
    static let appGroupIdentifier = "group.com.prvital"
    private static let key = "glucose.snapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func save(_ snapshot: GlucoseSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func load() -> GlucoseSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}
