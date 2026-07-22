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
    private static let reloadedDataAtKey = "glucose.snapshot.reloadedDataAt"

    /// Minimum spacing between reloads triggered by an *important* change — the
    /// glucose zone flipping, staleness, the target band, a prediction appearing.
    /// These are rare in practice, so they get the faster lane.
    private static let importantReloadInterval: TimeInterval = 10 * 60

    /// Minimum spacing between reloads triggered by a routine fresher reading in
    /// the same zone. WidgetKit only funds ~40–70 timeline reloads per day;
    /// reloading on every CGM reading (every ~5 min) blows that budget and
    /// freezes the widget — the exact bug this throttle fixes.
    private static let routineReloadInterval: TimeInterval = 20 * 60

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// The primary snapshot store: a plain file in the shared App Group container.
    /// A widget/watch process reads this instead of the `UserDefaults` plist, whose
    /// backing file inherited `NSFileProtectionComplete` on upgrading installs and
    /// so was unreadable exactly when Lock Screen / background widgets refresh — the
    /// "widgets show nothing" bug. This file is written with the relaxed protection
    /// class explicitly, so it stays readable after the first post-reboot unlock.
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: "glucose-snapshot.json")
    }

    static func save(_ snapshot: GlucoseSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Primary: the App Group file, written atomically with
        // CompleteUntilFirstUserAuthentication so the extensions can read it.
        if let fileURL {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        // Mirror into UserDefaults too, as a fallback reader for older extension
        // builds and to back the reload bookkeeping below.
        defaults.set(data, forKey: key)

        // Spend the scarce reload budget on two lanes:
        //  - important lane: the zone-based signature changed (zone, staleness,
        //    target band, prediction) — at most every 10 minutes;
        //  - routine lane: a genuinely newer reading in the same zone — at most
        //    every 20 minutes, so the shown value tracks reality at a sustainable
        //    cadence while the widget's own timeline policy backstops the rest.
        let signature = reloadSignature(snapshot)
        let lastSignature = defaults.string(forKey: signatureKey)
        let lastReload = defaults.double(forKey: reloadAtKey)
        let lastDataAt = defaults.double(forKey: reloadedDataAtKey)
        let now = Date().timeIntervalSince1970
        let elapsed = now - lastReload

        let importantChange = signature != lastSignature && elapsed > importantReloadInterval
        let fresherData = snapshot.updatedAt.timeIntervalSince1970 > lastDataAt
            && elapsed > routineReloadInterval
        guard importantChange || fresherData else { return }

        defaults.set(signature, forKey: signatureKey)
        defaults.set(now, forKey: reloadAtKey)
        defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: reloadedDataAtKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// A signature of only the snapshot's *important* state — zone, staleness,
    /// target band and whether a prediction is present. It deliberately EXCLUDES
    /// the value, timestamp and history, which change on every reading: those go
    /// through the slower routine lane instead. The relative "updated" caption
    /// advances on its own via `Text(_, style: .relative)`.
    private static func reloadSignature(_ s: GlucoseSnapshot) -> String {
        [
            s.zoneLabel, String(s.zoneColorHex), s.isStale ? "1" : "0",
            String(Int(s.targetLowerMgdL)), String(Int(s.targetUpperMgdL)),
            s.predictionText == nil ? "" : "predicting"
        ].joined(separator: "|")
    }

    /// Falls back to the honest `.empty` ("—", grey, stale) — never to the
    /// realistic-looking gallery placeholder, which a user could mistake for a
    /// real reading if the widget can't load data.
    static func load() -> GlucoseSnapshot {
        // Prefer the App Group file (readable after first unlock); fall back to the
        // UserDefaults mirror, then to the honest empty snapshot.
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) {
            return snapshot
        }
        if let data = defaults.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) {
            return snapshot
        }
        return .empty
    }
}
