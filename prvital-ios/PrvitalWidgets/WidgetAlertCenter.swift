import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Glucose alerts evaluated from the WIDGET's self-fetched reading — so an
/// urgent low still alerts when iOS gives the app no background runtime (the
/// widget's timeline refresh is often the only periodic runtime available).
///
/// It reads the SAME app-group keys as the app's `GlucoseAlertService` and
/// `CriticalAlarmScheduler` — preferences, thresholds, unit, alert state and
/// escalation anchor — and fires under the same notification identifiers.
/// Whichever process sees a reading first alerts; the shared state's snooze
/// and last-reading dedupe keep the other one quiet.
enum WidgetAlertCenter {
    // Key strings mirrored from Preferences.Keys / GlucoseAlertService /
    // CriticalAlarmScheduler — kept literal because those types are app-only.
    private static let alertPrefsKey = "pref.alerts"
    private static let thresholdsKey = "pref.thresholds"
    private static let unitKey = "pref.glucoseUnit"
    private static let stateKey = "glucose.alertState"
    private static let criticalPrefsKey = "pref.criticalAlarm"
    private static let anchorKey = "glucose.criticalAlarmAnchor"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroupIdentifier) ?? .standard
    }

    /// Runs the out-of-range evaluation for a freshly fetched sample, then the
    /// escalation arm / stand-down — mirroring `GlucoseAlertService.evaluate`.
    /// Cheap and idempotent: the shared state makes re-seeing a reading a no-op.
    static func evaluate(sample: NormalizedGlucoseSample, now: Date = Date()) {
        guard let prefsData = defaults.data(forKey: alertPrefsKey),
              let preferences = try? JSONDecoder().decode(AlertPreferences.self, from: prefsData),
              preferences.enabled else { return }
        let thresholds = defaults.data(forKey: thresholdsKey)
            .flatMap { try? JSONDecoder().decode(GlucoseThresholds.self, from: $0) } ?? .standard
        let unit = GlucoseUnit(rawValue: defaults.string(forKey: unitKey) ?? "") ?? .mgdL

        let reading = GlucoseAlertEvaluator.Reading(mgdL: sample.valueMgdL, timestamp: sample.timestamp)
        let decision = GlucoseAlertEvaluator.decide(
            reading: reading, thresholds: thresholds, preferences: preferences,
            unit: unit, last: loadState(), now: now)
        if let alert = decision.alert { fire(alert) }
        saveState(decision.state)

        // Escalation parity with the app: a fresh urgent-low alert arms the
        // pre-scheduled repeats; a recovered reading stands them down.
        guard now.timeIntervalSince(sample.timestamp) <= GlucoseAlertEvaluator.maxReadingAge else { return }
        if GlucoseAlertEvaluator.level(for: sample.valueMgdL, thresholds: thresholds) == .urgentLow {
            if decision.alert?.level == .urgentLow { armEscalation(now: now) }
        } else {
            standDownIfArmed()
        }
    }

    // MARK: State (same shape + key as GlucoseAlertService)

    private static func loadState() -> GlucoseAlertState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(GlucoseAlertState.self, from: data)
        else { return .empty }
        return state
    }

    private static func saveState(_ state: GlucoseAlertState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
    }

    // MARK: Delivery (same identifiers, sounds and levels as the app)

    private static func fire(_ alert: GlucoseAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        let sounds = AlertSoundStore.load()
        content.sound = (alert.level.severity >= 2 ? sounds.critical : sounds.important).notificationSound
        if alert.level.severity >= 2 {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        } else {
            content.relevanceScore = 0.6
        }
        if alert.level == .urgentLow, escalationPreferences().escalationEnabled {
            // The category (with its "I'm on it" action) is registered by the
            // app; referencing it here reuses that registration.
            content.categoryIdentifier = CriticalAlarmPlanner.categoryIdentifier
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "glucose-alert-\(alert.level.rawValue)", content: content, trigger: nil))
        #endif
    }

    // MARK: Escalation (same anchor + identifiers as CriticalAlarmScheduler)

    private static func escalationPreferences() -> CriticalAlarmPreferences {
        defaults.data(forKey: criticalPrefsKey)
            .flatMap { try? JSONDecoder().decode(CriticalAlarmPreferences.self, from: $0) } ?? .default
    }

    private static func armEscalation(now: Date) {
        #if canImport(UserNotifications)
        let preferences = escalationPreferences()
        let steps = CriticalAlarmPlanner.schedule(from: preferences)
        guard !steps.isEmpty else { return }

        if let data = try? JSONEncoder().encode(CriticalAlarmAnchor(
            firedAt: now, repeatMinutes: preferences.repeatMinutes, maxRepeats: preferences.maxRepeats)) {
            defaults.set(data, forKey: anchorKey)
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: CriticalAlarmPlanner.allRepeatIdentifiers)
        let criticalSound = AlertSoundStore.load().critical.notificationSound
        for step in steps {
            let copy = CriticalAlarmPlanner.repeatContent(index: step.index, total: steps.count)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = criticalSound
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
            content.categoryIdentifier = CriticalAlarmPlanner.categoryIdentifier
            center.add(UNNotificationRequest(
                identifier: CriticalAlarmPlanner.identifier(forRepeat: step.index),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, step.delaySeconds), repeats: false)))
        }
        #endif
    }

    private static func standDownIfArmed() {
        guard defaults.data(forKey: anchorKey) != nil else { return }
        defaults.removeObject(forKey: anchorKey)
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let identifiers = CriticalAlarmPlanner.allRepeatIdentifiers
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        #endif
    }
}
