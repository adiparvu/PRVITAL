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

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func save(_ snapshot: GlucoseSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Always keep the freshest snapshot on disk so the app/extension reads
        // current values. But WidgetKit gives each app a limited daily budget of
        // timeline reloads, so only *nudge* a reload when the snapshot's meaningful
        // content changed. The signature deliberately excludes now-relative text
        // (e.g. "1h ago"), which changes on every publish — reloading for that
        // alone would exhaust the budget and freeze the widgets. Relative captions
        // in the widget use `Text(_, style: .relative)`, which updates on its own.
        let signature = reloadSignature(snapshot)
        let changed = defaults.string(forKey: signatureKey) != signature
        defaults.set(data, forKey: key)
        guard changed else { return }
        defaults.set(signature, forKey: signatureKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// A signature of the snapshot's *stable* content — the reading, trend, zone,
    /// target band and history — excluding any now-relative formatted strings.
    private static func reloadSignature(_ s: GlucoseSnapshot) -> String {
        let points = s.points
            .map { "\(Int($0.date.timeIntervalSince1970)):\(Int($0.mgdL))" }
            .joined(separator: ",")
        return [
            s.valueText, s.unitText, String(Int(s.mgdL)), s.trendSymbol, s.trendLabel,
            s.zoneLabel, String(s.zoneColorHex), String(Int(s.updatedAt.timeIntervalSince1970)),
            s.isStale ? "1" : "0", String(Int(s.targetLowerMgdL)), String(Int(s.targetUpperMgdL)),
            s.sourceName, s.lastMealText ?? "", s.nextReminderText ?? "", s.predictionText ?? "", points
        ].joined(separator: "|")
    }

    static func load() -> GlucoseSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}
