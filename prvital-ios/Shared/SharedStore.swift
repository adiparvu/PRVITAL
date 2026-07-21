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
    private static let signatureKey = "glucose.snapshot.signature"
    private static let reloadAtKey = "glucose.snapshot.reloadedAt"

    /// Minimum spacing between app-triggered widget reloads. WidgetKit only funds
    /// ~40–70 timeline reloads per day; reloading on every CGM reading (every ~5
    /// min) blows that budget and freezes the widget. Routine same-zone value ticks
    /// are instead picked up by the widget's own timeline refresh policy.
    private static let minReloadInterval: TimeInterval = 10 * 60

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func save(_ snapshot: GlucoseSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Always keep the freshest snapshot on disk so the app/extension (and the
        // widget's next scheduled refresh) read current values.
        defaults.set(data, forKey: key)

        // Only *nudge* an immediate widget reload when something worth spending the
        // scarce reload budget on changed — the zone, staleness, target band, or a
        // new prediction — and never more than once per `minReloadInterval`. This is
        // the fix for widgets freezing: the old code reloaded on every reading, so
        // the daily budget was exhausted within an hour and no refresh (app-nudged
        // OR policy-scheduled) could get through afterwards.
        let signature = reloadSignature(snapshot)
        let lastSignature = defaults.string(forKey: signatureKey)
        let lastReload = defaults.double(forKey: reloadAtKey)
        let now = Date().timeIntervalSince1970
        guard signature != lastSignature, now - lastReload > minReloadInterval else { return }
        defaults.set(signature, forKey: signatureKey)
        defaults.set(now, forKey: reloadAtKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// A signature of only the snapshot's *important* state — zone, staleness,
    /// target band and whether a prediction is present. It deliberately EXCLUDES
    /// the value, timestamp and history, which change on every reading: reloading
    /// for those would exhaust WidgetKit's budget. The widget's timeline refresh
    /// policy handles routine value updates; the relative "updated" caption advances
    /// on its own via `Text(_, style: .relative)`.
    private static func reloadSignature(_ s: GlucoseSnapshot) -> String {
        [
            s.zoneLabel, String(s.zoneColorHex), s.isStale ? "1" : "0",
            String(Int(s.targetLowerMgdL)), String(Int(s.targetUpperMgdL)),
            s.predictionText == nil ? "" : "predicting"
        ].joined(separator: "|")
    }

    static func load() -> GlucoseSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}
