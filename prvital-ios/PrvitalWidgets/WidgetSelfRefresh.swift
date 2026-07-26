import Foundation

/// Lets the widget fetch the latest reading BY ITSELF when the app hasn't
/// republished lately — so the Home/Lock Screen numbers keep moving even while
/// iOS never wakes the app. Credentials come from the shared Keychain access
/// group; the result is written back to `SharedStore` (without a reload nudge)
/// so every widget kind and the watch pick it up on their own next reload.
///
/// This is display-only: the fetched sample is NOT imported into the journal —
/// the app backfills the full history through the normal sync the next time it
/// runs, using the same source-native IDs, so nothing duplicates.
enum WidgetSelfRefresh {
    /// While the published snapshot is at most this old, the app is doing its
    /// job — don't spend widget budget or network on a self-fetch.
    static let snapshotFreshFor: TimeInterval = 5.5 * 60

    /// Whether a credentialed CGM service is available to ask.
    static var canFetch: Bool {
        SourceCredentialStore.shared.hasCredentials(for: .dexcom)
            || SourceCredentialStore.shared.hasCredentials(for: .freeStyleLibre)
    }

    /// Returns a refreshed snapshot when the shared one has gone stale-ish AND a
    /// credentialed source returns a genuinely newer reading; nil otherwise.
    static func refreshIfStale(_ snapshot: GlucoseSnapshot, now: Date = Date()) async -> GlucoseSnapshot? {
        guard now.timeIntervalSince(snapshot.updatedAt) > snapshotFreshFor else { return nil }
        guard let sample = await latestSample(preferring: snapshot.sourceRaw) else { return nil }
        // Alerts run on every fetched reading, not only display-worthy ones:
        // the shared state dedupes against the app, and a recovered reading
        // must stand the urgent-low escalation down even when nothing new
        // needs rendering.
        WidgetAlertCenter.evaluate(sample: sample, now: now)
        guard sample.timestamp > snapshot.updatedAt else { return nil }
        return refreshed(snapshot, with: sample, now: now)
    }

    /// Asks the snapshot's own source first, then the other credentialed one.
    private static func latestSample(preferring raw: String?) async -> NormalizedGlucoseSample? {
        let store = SourceCredentialStore.shared
        var order: [DataSource] = [.dexcom, .freeStyleLibre]
        if let raw, let preferred = DataSource(rawValue: raw), order.contains(preferred) {
            order = [preferred] + order.filter { $0 != preferred }
        }
        for source in order {
            guard let credentials = store.read(for: source), credentials.isComplete else { continue }
            switch source {
            case .dexcom:
                let samples = try? await DexcomShareClient(credentials: credentials)
                    .fetchSamples(minutes: 60, maxCount: 12)
                if let sample = samples?.max(by: { $0.timestamp < $1.timestamp }) { return sample }
            case .freeStyleLibre:
                let samples = try? await LibreLinkUpClient(credentials: credentials).fetchSamples()
                if let sample = samples?.max(by: { $0.timestamp < $1.timestamp }) { return sample }
            default:
                break
            }
        }
        return nil
    }

    /// A display-refresh of the published snapshot: value, trend, zone, sparkline
    /// point and timestamps — through the same formatting and zone logic the app
    /// uses. Velocity-derived extras (forecast tail, prediction line) are cleared
    /// rather than left stale: the widget can't recompute them honestly.
    static func refreshed(_ snapshot: GlucoseSnapshot, with sample: NormalizedGlucoseSample,
                          now: Date = Date()) -> GlucoseSnapshot {
        var s = snapshot
        let unit = GlucoseUnit(rawValue: s.unitText) ?? .mgdL
        // The snapshot carries only the target band; the urgent bounds stay at
        // the clinical defaults — identical to most users' settings, and only
        // ever affecting the shade of an out-of-range colour.
        var thresholds = GlucoseThresholds.standard
        thresholds.targetLower = s.targetLowerMgdL
        thresholds.targetUpper = s.targetUpperMgdL
        let zone = thresholds.zone(forMgdL: sample.valueMgdL)

        s.mgdL = sample.valueMgdL
        s.valueText = GlucoseFormatting.string(mgdL: sample.valueMgdL, unit: unit)
        s.trendSymbol = sample.trend?.symbol ?? "arrow.right"
        s.trendLabel = sample.trend?.label ?? String(localized: "Stable")
        s.zoneLabel = zone.label
        s.zoneColorHex = hex(for: zone)
        s.sourceName = sample.source.displayName
        s.sourceRaw = sample.source.rawValue
        s.updatedAt = sample.timestamp
        s.isStale = now.timeIntervalSince(sample.timestamp) > 20 * 60

        if s.points.last.map({ sample.timestamp > $0.date }) ?? true {
            s.points.append(.init(date: sample.timestamp, mgdL: sample.valueMgdL))
        }
        let window = now.addingTimeInterval(-3 * 3600)
        s.points = Array(s.points.filter { $0.date >= window }.suffix(72))

        s.forecastMgdL = nil
        s.forecastAt = nil
        s.forecastLowMgdL = nil
        s.forecastHighMgdL = nil
        s.predictionText = nil
        return s
    }

    /// Same palette as `SnapshotPublisher.hex(for:)`.
    private static func hex(for zone: GlucoseZone) -> UInt {
        switch zone {
        case .veryLow: return 0xD64550
        case .low: return 0xE8730C
        case .inRange: return 0x2FB86B
        case .high: return 0xE0A100
        case .veryHigh: return 0xE8730C
        }
    }
}
