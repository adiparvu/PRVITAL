import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The live side of the critical-low "repeat until acknowledged" escalation:
/// schedules the follow-up notifications with the system, persists the armed
/// anchor, and stands everything down on acknowledgment, recovery, or opt-out.
/// All planning (schedule, identifiers, copy) is the pure `CriticalAlarmPlanner`.
///
/// Stateless by design: every member is static and touches only thread-safe
/// system objects (`UserDefaults`, `UNUserNotificationCenter`), so the
/// `nonisolated` members are safe to call from the notification delegate's
/// callbacks as well as from the main actor.
///
/// Because the repeats are pre-scheduled with the system the moment the
/// urgent-low alert fires, they keep firing even if the app gets no further
/// runtime — which is exactly when a safety net matters most. The automatic
/// stand-down on recovery, by contrast, can only run when the app evaluates a
/// fresh reading (foreground polling, HealthKit background delivery, or a
/// background refresh); that is the best recovery signal available for a
/// purely on-device feature without a server push.
enum CriticalAlarmScheduler {
    /// Must match `Preferences.Keys.criticalAlarm` (Preferences.swift), which
    /// persists `CriticalAlarmPreferences` as JSON in the app-group defaults.
    private static let preferencesKey = "pref.criticalAlarm"

    /// Where the armed-escalation anchor lives (same defaults suite).
    private static let anchorKey = "glucose.criticalAlarmAnchor"

    private nonisolated static var defaults: UserDefaults {
        UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    /// The user's current escalation preferences, read from the shared
    /// defaults (kept up to date by `Preferences.criticalAlarm`'s `didSet`).
    nonisolated static func loadPreferences() -> CriticalAlarmPreferences {
        guard let data = defaults.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode(CriticalAlarmPreferences.self, from: data)
        else { return .default }
        return value
    }

    nonisolated static var isEscalationEnabled: Bool {
        loadPreferences().escalationEnabled
    }

    /// True while an escalation is armed (an anchor is persisted).
    nonisolated static var isArmed: Bool {
        defaults.data(forKey: anchorKey) != nil
    }

    // MARK: Arm / restore

    /// Called right after an urgent-low alert fires. When escalation is on,
    /// persists the anchor and schedules the whole batch of follow-ups with
    /// `UNTimeIntervalNotificationTrigger`s, replacing any previous batch (the
    /// identifiers are stable, and stale higher-index leftovers are removed
    /// first). When escalation is off, makes sure nothing stays armed.
    @MainActor
    static func armForUrgentLow(now: Date = Date()) {
        let preferences = loadPreferences()
        let steps = CriticalAlarmPlanner.schedule(from: preferences)
        guard !steps.isEmpty else {
            standDownIfArmed()
            return
        }
        #if canImport(UserNotifications)
        // Make sure the "I'm on it" category is registered before a repeat can
        // be delivered (normally already done by `requestAuthorization`).
        NotificationScheduler.registerNotificationCategories()

        saveAnchor(CriticalAlarmAnchor(firedAt: now,
                                       repeatMinutes: preferences.repeatMinutes,
                                       maxRepeats: preferences.maxRepeats))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: CriticalAlarmPlanner.allRepeatIdentifiers)
        add(steps, total: steps.count, to: center)
        #endif
    }

    /// Re-schedules the repeats still due for an armed escalation. Called by
    /// `NotificationScheduler.reschedule`, whose wholesale clear of the pending
    /// queue would otherwise silently cancel an in-flight critical alarm.
    @MainActor
    static func restorePendingRepeats(now: Date = Date()) {
        #if canImport(UserNotifications)
        guard let anchor = loadAnchor() else { return }
        let remaining = CriticalAlarmPlanner.remainingSchedule(anchor: anchor, now: now)
        guard !remaining.isEmpty else {
            clearAnchor()
            return
        }
        add(remaining,
            total: CriticalAlarmPlanner.schedule(anchor: anchor).count,
            to: UNUserNotificationCenter.current())
        #endif
    }

    // MARK: Stand down

    /// Cancels every pending repeat, clears the delivered ones from
    /// Notification Center (the original urgent-low alert is deliberately left
    /// in place), and forgets the anchor. Safe to call at any time, from any
    /// isolation — used on acknowledgment (notification tap or "I'm on it"),
    /// on recovery, and when the user turns the feature off.
    nonisolated static func standDown() {
        clearAnchor()
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let identifiers = CriticalAlarmPlanner.allRepeatIdentifiers
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        #endif
    }

    /// `standDown()`, but skipping the notification-center calls when nothing
    /// is armed — cheap enough to run on every evaluated reading.
    nonisolated static func standDownIfArmed() {
        guard isArmed else { return }
        standDown()
    }

    // MARK: Private

    #if canImport(UserNotifications)
    @MainActor
    private static func add(_ steps: [CriticalAlarmRepeatStep], total: Int, to center: UNUserNotificationCenter) {
        let criticalSound = AlertSoundStore.load().critical.notificationSound
        for step in steps {
            let copy = CriticalAlarmPlanner.repeatContent(index: step.index, total: total)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = criticalSound
            // Same treatment as the urgent alerts themselves: time-sensitive so
            // the repeats break through Focus and scheduled summaries (honoured
            // via the app's Time Sensitive Notifications entitlement), pinned
            // to the top of any summary.
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
            content.categoryIdentifier = CriticalAlarmPlanner.categoryIdentifier
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, step.delaySeconds), repeats: false)
            center.add(UNNotificationRequest(
                identifier: CriticalAlarmPlanner.identifier(forRepeat: step.index),
                content: content,
                trigger: trigger))
        }
    }
    #endif

    private nonisolated static func loadAnchor() -> CriticalAlarmAnchor? {
        guard let data = defaults.data(forKey: anchorKey) else { return nil }
        return try? JSONDecoder().decode(CriticalAlarmAnchor.self, from: data)
    }

    private nonisolated static func saveAnchor(_ anchor: CriticalAlarmAnchor) {
        if let data = try? JSONEncoder().encode(anchor) {
            defaults.set(data, forKey: anchorKey)
        }
    }

    private nonisolated static func clearAnchor() {
        defaults.removeObject(forKey: anchorKey)
    }
}
