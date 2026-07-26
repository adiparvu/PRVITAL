import Foundation

/// Repeat-until-acknowledged escalation for urgent-low alerts. Off by default;
/// when on, the urgent-low notification re-fires every `repeatMinutes` until the
/// user acknowledges it or `maxRepeats` is reached. Lives here (not in
/// Preferences.swift) so the widget's alert evaluation can compile it too.
struct CriticalAlarmPreferences: Codable, Equatable, Sendable {
    var escalationEnabled: Bool = false
    var repeatMinutes: Int = 5
    var maxRepeats: Int = 6

    static let `default` = CriticalAlarmPreferences()
}

/// A snapshot of an armed critical-low escalation: when the urgent-low alert
/// fired and the repeat cadence configured at that moment. Persisted (as JSON
/// in the shared defaults) so the pending repeats can be rebuilt after the
/// reminder scheduler wholesale-clears pending notifications, and cleared when
/// the escalation is acknowledged or glucose recovers.
struct CriticalAlarmAnchor: Codable, Equatable, Sendable {
    var firedAt: Date
    var repeatMinutes: Int
    var maxRepeats: Int
}

/// One planned follow-up notification: its 1-based index and the delay (in
/// seconds) from the reference date it was planned against.
struct CriticalAlarmRepeatStep: Equatable, Sendable {
    let index: Int
    let delaySeconds: TimeInterval
}

/// Pure planning logic for the critical-low "repeat until acknowledged"
/// escalation: the identifier scheme, the repeat schedule, and the follow-up
/// copy. No UserNotifications dependency, so it is fully unit-testable; the
/// live side (scheduling, cancelling) lives in `CriticalAlarmScheduler`.
enum CriticalAlarmPlanner {
    // MARK: Identifiers

    /// Prefix for every scheduled follow-up ("critical-repeat-1", ...), so the
    /// whole batch can be cancelled at once without touching any other pending
    /// request (fixed-clock reminders, "contextual-" nudges, ...).
    static let repeatIdentifierPrefix = "critical-repeat-"

    /// The actionable category attached to the urgent-low alert and its repeats.
    static let categoryIdentifier = "critical-alarm"

    /// The "I'm on it" acknowledge action on that category.
    static let acknowledgeActionIdentifier = "critical-alarm-acknowledge"

    /// The immediate urgent-low alert fired by `GlucoseAlertService`, which
    /// names its requests "glucose-alert-<level raw value>". Tapping it counts
    /// as acknowledging the escalation.
    static let urgentLowAlertIdentifier = "glucose-alert-\(GlucoseAlertLevel.urgentLow.rawValue)"

    /// Hard safety cap on how many follow-ups can ever be scheduled, regardless
    /// of preferences. Also bounds the identifier space, so cancellation can
    /// enumerate every possible identifier instead of querying the queue.
    static let absoluteMaxRepeats = 20

    static func identifier(forRepeat index: Int) -> String {
        repeatIdentifierPrefix + String(index)
    }

    /// Parses "critical-repeat-3" into 3. Nil for anything else.
    static func repeatIndex(from identifier: String) -> Int? {
        guard identifier.hasPrefix(repeatIdentifierPrefix),
              let index = Int(identifier.dropFirst(repeatIdentifierPrefix.count)),
              index >= 1
        else { return nil }
        return index
    }

    static func isRepeatIdentifier(_ identifier: String) -> Bool {
        repeatIndex(from: identifier) != nil
    }

    /// Every identifier a repeat could have been scheduled under — used to
    /// cancel the whole batch (removing a non-pending identifier is a no-op).
    static var allRepeatIdentifiers: [String] {
        (1...absoluteMaxRepeats).map(identifier(forRepeat:))
    }

    /// Whether a *default tap* (opening the notification) on this identifier
    /// counts as acknowledging the escalation: the urgent-low alert itself or
    /// any of its repeats.
    static func acknowledgeCancelsRepeats(notificationIdentifier: String) -> Bool {
        notificationIdentifier == urgentLowAlertIdentifier || isRepeatIdentifier(notificationIdentifier)
    }

    // MARK: Schedule

    /// The follow-ups to schedule when an urgent-low alert fires, with delays
    /// relative to the moment it fired. Empty when escalation is off; cadence
    /// and count are defensively clamped (at least 1 minute apart, at most
    /// `absoluteMaxRepeats` repeats).
    static func schedule(from preferences: CriticalAlarmPreferences) -> [CriticalAlarmRepeatStep] {
        guard preferences.escalationEnabled else { return [] }
        return steps(repeatMinutes: preferences.repeatMinutes, maxRepeats: preferences.maxRepeats)
    }

    /// The full planned run for an armed escalation (delays relative to the
    /// moment the urgent-low alert fired).
    static func schedule(anchor: CriticalAlarmAnchor) -> [CriticalAlarmRepeatStep] {
        steps(repeatMinutes: anchor.repeatMinutes, maxRepeats: anchor.maxRepeats)
    }

    /// The follow-ups still in the future for an armed escalation, with delays
    /// re-based onto `now` — used to re-schedule after the pending queue was
    /// cleared wholesale. Empty once the run is over.
    static func remainingSchedule(anchor: CriticalAlarmAnchor, now: Date) -> [CriticalAlarmRepeatStep] {
        schedule(anchor: anchor).compactMap { step in
            let delay = anchor.firedAt.timeIntervalSince(now) + step.delaySeconds
            guard delay >= 1 else { return nil }
            return CriticalAlarmRepeatStep(index: step.index, delaySeconds: delay)
        }
    }

    private static func steps(repeatMinutes: Int, maxRepeats: Int) -> [CriticalAlarmRepeatStep] {
        let minutes = min(max(repeatMinutes, 1), 120)
        let count = min(max(maxRepeats, 0), absoluteMaxRepeats)
        guard count >= 1 else { return [] }
        return (1...count).map {
            CriticalAlarmRepeatStep(index: $0, delaySeconds: TimeInterval($0 * minutes * 60))
        }
    }

    // MARK: Copy

    /// Follow-up copy. Deliberately value-free: minutes have passed since the
    /// reading that triggered the alert, so repeating the old number could
    /// mislead — the message asks for a fresh check instead.
    static func repeatContent(index: Int, total: Int) -> (title: String, body: String) {
        (
            title: String(localized: "Urgent low — still unacknowledged"),
            body: String(localized: "Your urgent low alert hasn't been acknowledged. Check your glucose and treat if needed. (Reminder \(index) of \(total))")
        )
    }
}
