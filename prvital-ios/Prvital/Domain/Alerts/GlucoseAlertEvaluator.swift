import Foundation

/// The severity levels a glucose reading can trigger. In-range readings produce
/// no level (and clear any prior alert state).
enum GlucoseAlertLevel: String, Codable, CaseIterable, Sendable {
    case urgentLow, low, high, urgentHigh

    /// How severe the level is (2 = urgent, 1 = out of range). Used to decide
    /// whether a change should bypass the snooze window.
    var severity: Int { self == .urgentLow || self == .urgentHigh ? 2 : 1 }
}

/// User settings for reactive glucose alerts. Off by default; the user opts in
/// and picks which levels to be notified about.
struct AlertPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var urgentLow = true
    var low = true
    var high = true
    var urgentHigh = true
    /// Minimum minutes between repeat alerts for the *same* level.
    var snoozeMinutes = 20

    // MARK: Rate-of-change (Wave 7 alerts hub)
    //
    // Opt-in "glucose is moving fast" alerts, independent of the value being in
    // or out of range — a steep rise or fall is worth catching early.

    /// Alert when glucose is climbing faster than `rateThresholdPerMinute`.
    var riseRateEnabled = false
    /// Alert when glucose is dropping faster than `rateThresholdPerMinute`.
    var fallRateEnabled = false
    /// Rate threshold in mg/dL per minute (≈ 3 is a "rising/falling fast" trend).
    var rateThresholdPerMinute = 3.0

    // MARK: Signal loss

    /// Alert when no new reading has arrived for `signalLossMinutes`.
    var signalLossEnabled = false
    var signalLossMinutes = 25

    static let `default` = AlertPreferences()

    func isEnabled(_ level: GlucoseAlertLevel) -> Bool {
        switch level {
        case .urgentLow: return urgentLow
        case .low: return low
        case .high: return high
        case .urgentHigh: return urgentHigh
        }
    }

    /// Whether any alert category is switched on (drives the hub's summary).
    var anyCategoryEnabled: Bool {
        enabled && (urgentLow || low || high || urgentHigh || riseRateEnabled || fallRateEnabled || signalLossEnabled)
    }

    // A tolerant decoder so settings saved before the rate-of-change and
    // signal-loss fields existed still decode with the user's out-of-range
    // choices intact. Without this the missing keys would throw, `try?` would
    // fall back to `.default`, and an app update would silently switch a user's
    // alerts *off* — a safety regression. `encode(to:)` stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case enabled, urgentLow, low, high, urgentHigh, snoozeMinutes
        case riseRateEnabled, fallRateEnabled, rateThresholdPerMinute
        case signalLossEnabled, signalLossMinutes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        urgentLow = try c.decodeIfPresent(Bool.self, forKey: .urgentLow) ?? true
        low = try c.decodeIfPresent(Bool.self, forKey: .low) ?? true
        high = try c.decodeIfPresent(Bool.self, forKey: .high) ?? true
        urgentHigh = try c.decodeIfPresent(Bool.self, forKey: .urgentHigh) ?? true
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 20
        riseRateEnabled = try c.decodeIfPresent(Bool.self, forKey: .riseRateEnabled) ?? false
        fallRateEnabled = try c.decodeIfPresent(Bool.self, forKey: .fallRateEnabled) ?? false
        rateThresholdPerMinute = try c.decodeIfPresent(Double.self, forKey: .rateThresholdPerMinute) ?? 3.0
        signalLossEnabled = try c.decodeIfPresent(Bool.self, forKey: .signalLossEnabled) ?? false
        signalLossMinutes = try c.decodeIfPresent(Int.self, forKey: .signalLossMinutes) ?? 25
    }
}

/// A ready-to-present alert (display strings only — no medical logic downstream).
struct GlucoseAlert: Equatable, Sendable {
    let level: GlucoseAlertLevel
    let title: String
    let body: String
}

/// The persisted state the evaluator needs to avoid duplicate and spammy alerts:
/// the last level alerted, when, and the timestamp of the last reading it acted
/// on (so the same reading is never alerted twice).
struct GlucoseAlertState: Codable, Equatable, Sendable {
    var lastLevel: String?
    var lastFiredAt: Date?
    var lastReadingAt: Date?

    static let empty = GlucoseAlertState()
}

/// Pure decision logic for reactive glucose alerts — a deterministic function of
/// the reading, thresholds, preferences and prior state, so it is fully testable
/// and never touches the notification system directly.
enum GlucoseAlertEvaluator {
    struct Reading: Equatable, Sendable {
        let mgdL: Double
        let timestamp: Date
    }

    struct Decision: Equatable, Sendable {
        let alert: GlucoseAlert?
        let state: GlucoseAlertState
    }

    /// Readings older than this are ignored — opening the app after a gap should
    /// not fire an alert about a stale value.
    static let maxReadingAge: TimeInterval = 15 * 60

    static func level(for mgdL: Double, thresholds: GlucoseThresholds) -> GlucoseAlertLevel? {
        switch thresholds.zone(forMgdL: mgdL) {
        case .veryLow: return .urgentLow
        case .low: return .low
        case .inRange: return nil
        case .high: return .high
        case .veryHigh: return .urgentHigh
        }
    }

    static func decide(
        reading: Reading,
        thresholds: GlucoseThresholds,
        preferences: AlertPreferences,
        unit: GlucoseUnit,
        last: GlucoseAlertState,
        now: Date
    ) -> Decision {
        // Master switch off, reading too old, or the very same reading already
        // handled → do nothing and leave state untouched.
        guard preferences.enabled,
              now.timeIntervalSince(reading.timestamp) <= maxReadingAge,
              last.lastReadingAt != reading.timestamp
        else { return Decision(alert: nil, state: last) }

        // In range (or a level the user disabled): remember we processed this
        // reading and clear the level so the next excursion alerts immediately.
        guard let level = level(for: reading.mgdL, thresholds: thresholds),
              preferences.isEnabled(level)
        else {
            var state = last
            state.lastLevel = nil
            state.lastReadingAt = reading.timestamp
            return Decision(alert: nil, state: state)
        }

        // Snooze only when the level is unchanged; any change in level (worse,
        // better, or crossing the range) alerts right away. Urgent levels
        // (severity 2 — urgent low/high) re-alert much sooner than the user's
        // snooze so a persistent severe low keeps nagging.
        let effectiveSnooze = level.severity >= 2 ? min(preferences.snoozeMinutes, 5) : preferences.snoozeMinutes
        if level.rawValue == last.lastLevel, let firedAt = last.lastFiredAt,
           now.timeIntervalSince(firedAt) < TimeInterval(max(0, effectiveSnooze) * 60) {
            var state = last
            state.lastReadingAt = reading.timestamp
            return Decision(alert: nil, state: state)
        }

        let alert = makeAlert(level: level, mgdL: reading.mgdL, unit: unit)
        let state = GlucoseAlertState(lastLevel: level.rawValue, lastFiredAt: now, lastReadingAt: reading.timestamp)
        return Decision(alert: alert, state: state)
    }

    static func makeAlert(level: GlucoseAlertLevel, mgdL: Double, unit: GlucoseUnit) -> GlucoseAlert {
        let value = GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)
        // Notification strings are localized here (String(localized:)); the value
        // is interpolated as a `%@` argument, so translations keep the placeholder.
        switch level {
        case .urgentLow:
            return GlucoseAlert(level: level,
                                title: String(localized: "Urgent low glucose"),
                                body: String(localized: "\(value) — treat now."))
        case .low:
            return GlucoseAlert(level: level,
                                title: String(localized: "Low glucose"),
                                body: String(localized: "\(value) — below your range."))
        case .high:
            return GlucoseAlert(level: level,
                                title: String(localized: "High glucose"),
                                body: String(localized: "\(value) — above your range."))
        case .urgentHigh:
            return GlucoseAlert(level: level,
                                title: String(localized: "Very high glucose"),
                                body: String(localized: "\(value) — check for ketones and follow your plan."))
        }
    }
}
