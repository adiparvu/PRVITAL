import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Delivers reactive glucose alerts. It owns the notification center and the
/// persisted `GlucoseAlertState`; the *decision* of whether to alert is made by
/// the pure `GlucoseAlertEvaluator`, so this type only fetches state, calls the
/// evaluator, and fires a local notification when told to.
@MainActor
final class GlucoseAlertService {
    private let defaults: UserDefaults
    private static let stateKey = "glucose.alertState"

    #if canImport(UserNotifications)
    private let center = UNUserNotificationCenter.current()
    #endif

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    /// Evaluates the current reading and fires a notification if warranted.
    /// Called after any data change once the snapshot is rebuilt.
    func evaluate(
        current: GlucoseAlertEvaluator.Reading?,
        thresholds: GlucoseThresholds,
        preferences: AlertPreferences,
        unit: GlucoseUnit,
        now: Date = Date()
    ) {
        guard preferences.enabled, let current else { return }
        let decision = GlucoseAlertEvaluator.decide(
            reading: current, thresholds: thresholds, preferences: preferences,
            unit: unit, last: loadState(), now: now
        )
        if let alert = decision.alert { fire(alert) }
        saveState(decision.state)

        // Critical-low escalation (opt-in "repeat until acknowledged"):
        //  - a fresh urgent-low alert arms a batch of follow-up notifications
        //    that the system delivers even if the app gets no more runtime;
        //  - a fresh reading back at/above the urgent-low threshold stands the
        //    batch down automatically. That recovery check runs whenever the
        //    app evaluates a new snapshot (foreground polling, HealthKit
        //    background delivery, or a background refresh) — the best signal
        //    available without a server; if the app never gets to evaluate,
        //    the repeats simply run until acknowledged or the configured cap.
        guard now.timeIntervalSince(current.timestamp) <= GlucoseAlertEvaluator.maxReadingAge else { return }
        if GlucoseAlertEvaluator.level(for: current.mgdL, thresholds: thresholds) == .urgentLow {
            if decision.alert?.level == .urgentLow {
                CriticalAlarmScheduler.armForUrgentLow(now: now)
            }
        } else {
            CriticalAlarmScheduler.standDownIfArmed()
        }
    }

    /// Fires an early, opt-in warning when a low is *imminent* (projected within
    /// the next several minutes) — before glucose has actually crossed the low
    /// threshold, giving lead time to treat. Gated on the same enabled/low toggles
    /// as reactive low alerts, with its own snooze so a slow decline doesn't fire
    /// every poll. When glucose is no longer trending low, the snooze resets so a
    /// fresh decline warns promptly.
    func evaluatePredictiveLow(
        projection: GlucoseProjection?,
        preferences: AlertPreferences,
        now: Date = Date()
    ) {
        guard preferences.enabled, preferences.low else { return }
        guard let projection, projection.kind == .low else {
            defaults.removeObject(forKey: Self.predictiveKey)
            return
        }
        if let last = defaults.object(forKey: Self.predictiveKey) as? Double,
           now.timeIntervalSince1970 - last < 20 * 60 {
            return
        }
        defaults.set(now.timeIntervalSince1970, forKey: Self.predictiveKey)
        firePredictiveLow(minutes: projection.minutes)
    }

    // MARK: State

    private static let predictiveKey = "glucose.predictiveLowFiredAt"

    private func loadState() -> GlucoseAlertState {
        guard let data = defaults.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(GlucoseAlertState.self, from: data)
        else { return .empty }
        return state
    }

    private func saveState(_ state: GlucoseAlertState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    // MARK: Delivery

    private func fire(_ alert: GlucoseAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        // Urgent lows and highs are time-critical. Raising the interruption level
        // to .timeSensitive lets them break through Focus and scheduled-summary
        // (honoured when the app carries the Time Sensitive Notifications
        // capability). Out-of-range but non-urgent alerts stay at the default
        // level. relevanceScore keeps the urgent one at the top of a summary.
        if alert.level.severity >= 2 {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        } else {
            content.relevanceScore = 0.6
        }

        // With escalation on, the urgent-low alert carries the critical-alarm
        // category so it shows the "I'm on it" acknowledge action — and a plain
        // tap on it also cancels the scheduled repeats (see the notification
        // delegate).
        if alert.level == .urgentLow, CriticalAlarmScheduler.isEscalationEnabled {
            content.categoryIdentifier = CriticalAlarmPlanner.categoryIdentifier
        }

        // One pending notification per level: a fresh alert of the same level
        // updates rather than stacks.
        let request = UNNotificationRequest(
            identifier: "glucose-alert-\(alert.level.rawValue)",
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }

    private func firePredictiveLow(minutes: Int) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Low predicted")
        content.body = String(localized: "Your glucose may drop below range in about \(minutes) min. A quick check or a small snack can head it off.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 0.9
        let request = UNNotificationRequest(
            identifier: "glucose-predictive-low",
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }
}
