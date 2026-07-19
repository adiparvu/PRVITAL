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

    static let `default` = AlertPreferences()

    func isEnabled(_ level: GlucoseAlertLevel) -> Bool {
        switch level {
        case .urgentLow: return urgentLow
        case .low: return low
        case .high: return high
        case .urgentHigh: return urgentHigh
        }
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
        // better, or crossing the range) alerts right away.
        if level.rawValue == last.lastLevel, let firedAt = last.lastFiredAt,
           now.timeIntervalSince(firedAt) < TimeInterval(max(0, preferences.snoozeMinutes) * 60) {
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
        switch level {
        case .urgentLow:
            return GlucoseAlert(level: level, title: "Urgent low glucose",
                                body: "\(value) — treat now.")
        case .low:
            return GlucoseAlert(level: level, title: "Low glucose",
                                body: "\(value) — below your range.")
        case .high:
            return GlucoseAlert(level: level, title: "High glucose",
                                body: "\(value) — above your range.")
        case .urgentHigh:
            return GlucoseAlert(level: level, title: "Very high glucose",
                                body: "\(value) — check for ketones and follow your plan.")
        }
    }
}
