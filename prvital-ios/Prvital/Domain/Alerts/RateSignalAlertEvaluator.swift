import Foundation

// MARK: - Rate of change

/// Direction of a rate-of-change alert.
enum RateAlertKind: String, Codable, Sendable { case rising, falling }

/// A ready-to-present rate-of-change alert (display strings only).
struct RateAlert: Equatable, Sendable {
    let kind: RateAlertKind
    let title: String
    let body: String
}

/// Persisted state so a sustained fast trend doesn't alert on every poll and the
/// same reading is never alerted twice.
struct RateAlertState: Codable, Equatable, Sendable {
    var lastKind: String?
    var lastFiredAt: Date?
    var lastReadingAt: Date?

    static let empty = RateAlertState()
}

/// Pure decision logic for "glucose is moving fast" alerts — rising or falling
/// faster than the user's threshold — independent of whether the value itself is
/// in range. Deterministic and side-effect-free, like `GlucoseAlertEvaluator`.
enum RateOfChangeAlertEvaluator {
    /// Readings older than this don't fire a rate alert (a stale trend is noise).
    static let maxReadingAge: TimeInterval = 15 * 60

    struct Decision: Equatable, Sendable {
        let alert: RateAlert?
        let state: RateAlertState
    }

    static func decide(
        mgdL: Double,
        perMinute: Double,
        timestamp: Date,
        thresholdPerMinute: Double,
        preferences: AlertPreferences,
        unit: GlucoseUnit,
        last: RateAlertState,
        now: Date
    ) -> Decision {
        guard preferences.enabled, (preferences.riseRateEnabled || preferences.fallRateEnabled),
              now.timeIntervalSince(timestamp) <= maxReadingAge,
              last.lastReadingAt != timestamp
        else { return Decision(alert: nil, state: last) }

        let threshold = max(0.5, thresholdPerMinute)
        let kind: RateAlertKind?
        if perMinute >= threshold, preferences.riseRateEnabled { kind = .rising }
        else if perMinute <= -threshold, preferences.fallRateEnabled { kind = .falling }
        else { kind = nil }

        // Not moving fast (or that direction is off): remember we saw this reading
        // and clear the level so the next fast move alerts immediately.
        guard let kind else {
            var state = last
            state.lastKind = nil
            state.lastReadingAt = timestamp
            return Decision(alert: nil, state: state)
        }

        // Snooze only while the same direction persists; a change of direction
        // alerts right away.
        if kind.rawValue == last.lastKind, let firedAt = last.lastFiredAt,
           now.timeIntervalSince(firedAt) < TimeInterval(max(0, preferences.snoozeMinutes) * 60) {
            var state = last
            state.lastReadingAt = timestamp
            return Decision(alert: nil, state: state)
        }

        let alert = makeAlert(kind: kind, mgdL: mgdL, unit: unit)
        let state = RateAlertState(lastKind: kind.rawValue, lastFiredAt: now, lastReadingAt: timestamp)
        return Decision(alert: alert, state: state)
    }

    static func makeAlert(kind: RateAlertKind, mgdL: Double, unit: GlucoseUnit) -> RateAlert {
        let value = GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)
        switch kind {
        case .rising:
            return RateAlert(kind: kind,
                             title: String(localized: "Glucose rising fast"),
                             body: String(localized: "\(value) and climbing quickly."))
        case .falling:
            return RateAlert(kind: kind,
                             title: String(localized: "Glucose falling fast"),
                             body: String(localized: "\(value) and dropping quickly — keep fast carbs handy."))
        }
    }
}

// MARK: - Signal loss

/// A ready-to-present "no data" alert.
struct SignalLossAlert: Equatable, Sendable {
    let title: String
    let body: String
}

/// Persisted state so a single gap fires once, keyed by the last reading before
/// it — a new reading resets the key so the next gap can fire again.
struct SignalLossState: Codable, Equatable, Sendable {
    var firedForReadingAt: Date?

    static let empty = SignalLossState()
}

/// Pure decision logic for a sensor/connection dropout: no new reading for longer
/// than the user's window.
enum SignalLossAlertEvaluator {
    struct Decision: Equatable, Sendable {
        let alert: SignalLossAlert?
        let state: SignalLossState
    }

    static func decide(
        lastReadingAt: Date?,
        preferences: AlertPreferences,
        last: SignalLossState,
        now: Date
    ) -> Decision {
        // Off, or no readings ever recorded → nothing to warn about; clear state.
        guard preferences.enabled, preferences.signalLossEnabled, let lastReadingAt else {
            return Decision(alert: nil, state: .empty)
        }

        let gap = now.timeIntervalSince(lastReadingAt)
        let window = TimeInterval(max(5, preferences.signalLossMinutes) * 60)

        guard gap >= window else {
            // Data is fresh again — reset so a future gap can alert.
            return Decision(alert: nil, state: .empty)
        }

        // Already alerted for this gap (same last-reading anchor) → stay quiet.
        if last.firedForReadingAt == lastReadingAt {
            return Decision(alert: nil, state: last)
        }

        let minutes = Int(gap / 60)
        let alert = SignalLossAlert(
            title: String(localized: "No recent readings"),
            body: String(localized: "No new glucose data for \(minutes) min. Check your sensor or connection.")
        )
        return Decision(alert: alert, state: SignalLossState(firedForReadingAt: lastReadingAt))
    }
}
