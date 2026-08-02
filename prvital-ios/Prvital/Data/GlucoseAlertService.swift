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
        if let alert = decision.alert {
            fire(alert)
            // The same moment, on the Lock Screen and in the Dynamic Island: the
            // loud alert presentation with what to do about it, holding the Island
            // for a couple of minutes before the live reading takes it back.
            GlucoseLiveActivityManager.shared.presentGlucoseAlert(
                isLow: alert.level == .urgentLow || alert.level == .low)
        }
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

    /// Fires a rate-of-change alert when glucose is rising or falling faster than
    /// the user's threshold. Uses its own persisted state and snooze so a
    /// sustained fast trend doesn't alert every poll.
    func evaluateRateOfChange(
        current: GlucoseAlertEvaluator.Reading?,
        perMinute: Double?,
        preferences: AlertPreferences,
        unit: GlucoseUnit,
        now: Date = Date()
    ) {
        guard preferences.enabled, (preferences.riseRateEnabled || preferences.fallRateEnabled),
              let current, let perMinute else { return }
        let decision = RateOfChangeAlertEvaluator.decide(
            mgdL: current.mgdL, perMinute: perMinute, timestamp: current.timestamp,
            thresholdPerMinute: preferences.rateThresholdPerMinute,
            preferences: preferences, unit: unit, last: loadRateState(), now: now
        )
        if let alert = decision.alert { fireRate(alert) }
        saveRateState(decision.state)
    }

    /// Nudges when a bolus looks forgotten: a logged meal with no dose around
    /// it, or a fast unlogged climb. The pure evaluator decides; this persists
    /// its memory (which meals were nudged, rise cooldown) and delivers.
    func evaluateMissedBolus(
        carbs: [MissedBolusEvaluator.CarbEvent],
        doses: [MissedBolusEvaluator.DoseEvent],
        points: [MissedBolusEvaluator.Point],
        preferences: AlertPreferences,
        now: Date = Date()
    ) {
        guard preferences.enabled, preferences.missedBolusEnabled else { return }
        let decision = MissedBolusEvaluator.decide(
            carbs: carbs, doses: doses, points: points,
            state: loadMissedBolusState(), now: now)
        if let alert = decision.alert { fireMissedBolus(alert) }
        saveMissedBolusState(decision.state)
    }

    /// The smart basal nudge: usual time passed, nothing logged today.
    func evaluateMissedBasal(
        basalDoseTimes: [Date],
        preferences: AlertPreferences,
        now: Date = Date()
    ) {
        guard preferences.enabled, preferences.basalNudgeEnabled else { return }
        let lastFired = defaults.object(forKey: Self.missedBasalDayKey) as? Date
        let decision = MissedBasalEvaluator.decide(
            now: now,
            usualMinutesFromMidnight: preferences.basalNudgeMinutesFromMidnight,
            basalDoseTimes: basalDoseTimes,
            lastFiredDay: lastFired)
        if decision.fire {
            fireMissedBasal()
            defaults.set(decision.lastFiredDay, forKey: Self.missedBasalDayKey)
        }
    }

    private static let missedBasalDayKey = "glucose.missedBasalFiredDay"

    private func fireMissedBasal() {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Basal logged yet?")
        content.body = String(localized: "Your usual basal time has passed and nothing is logged today. If you took it, log it — if not, better now than later.")
        content.sound = AlertSoundStore.load().important.notificationSound
        content.relevanceScore = 0.7
        let request = UNNotificationRequest(
            identifier: "glucose-missed-basal",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    /// Fires a "no recent readings" alert once per data gap.
    func evaluateSignalLoss(
        lastReadingAt: Date?,
        preferences: AlertPreferences,
        now: Date = Date()
    ) {
        guard preferences.enabled, preferences.signalLossEnabled else { return }
        let decision = SignalLossAlertEvaluator.decide(
            lastReadingAt: lastReadingAt, preferences: preferences,
            last: loadSignalState(), now: now
        )
        if let alert = decision.alert { fireSignalLoss(alert) }
        saveSignalState(decision.state)
    }

    // MARK: State

    private static let predictiveKey = "glucose.predictiveLowFiredAt"
    private static let rateStateKey = "glucose.rateAlertState"
    private static let signalStateKey = "glucose.signalLossState"
    private static let missedBolusStateKey = "glucose.missedBolusState"

    private func loadMissedBolusState() -> MissedBolusState {
        guard let data = defaults.data(forKey: Self.missedBolusStateKey),
              let state = try? JSONDecoder().decode(MissedBolusState.self, from: data)
        else { return .empty }
        return state
    }
    private func saveMissedBolusState(_ state: MissedBolusState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.missedBolusStateKey) }
    }

    private func loadRateState() -> RateAlertState {
        guard let data = defaults.data(forKey: Self.rateStateKey),
              let state = try? JSONDecoder().decode(RateAlertState.self, from: data)
        else { return .empty }
        return state
    }
    private func saveRateState(_ state: RateAlertState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.rateStateKey) }
    }
    private func loadSignalState() -> SignalLossState {
        guard let data = defaults.data(forKey: Self.signalStateKey),
              let state = try? JSONDecoder().decode(SignalLossState.self, from: data)
        else { return .empty }
        return state
    }
    private func saveSignalState(_ state: SignalLossState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.signalStateKey) }
    }

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
        // Urgent levels use the critical sound choice, the rest the important
        // one — each category carries the user's mode (sound / vibration only /
        // silent) and tone.
        let sounds = AlertSoundStore.load()
        content.sound = (alert.level.severity >= 2 ? sounds.critical : sounds.important).notificationSound

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

    private func fireRate(_ alert: RateAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        // A fast fall can precede a hypo — it sounds like the critical
        // category; a fast rise stays with the important one.
        let sounds = AlertSoundStore.load()
        content.sound = (alert.kind == .falling ? sounds.critical : sounds.important).notificationSound
        // A fast fall is treated as time-sensitive so it can break through Focus;
        // a fast rise stays at the default level.
        if alert.kind == .falling {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.85
        } else {
            content.relevanceScore = 0.5
        }
        // One pending notification per direction: a fresh alert updates rather
        // than stacks.
        let request = UNNotificationRequest(
            identifier: "glucose-rate-\(alert.kind.rawValue)",
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }

    private func fireSignalLoss(_ alert: SignalLossAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = AlertSoundStore.load().important.notificationSound
        content.relevanceScore = 0.4
        let request = UNNotificationRequest(
            identifier: "glucose-signal-loss",
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }

    private func fireMissedBolus(_ alert: MissedBolusAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .loggedMeal:
            let grams = Int((alert.grams ?? 0).rounded())
            let minutes = alert.minutesAgo ?? 0
            content.title = String(localized: "Meal without a bolus?")
            content.body = String(localized: "You logged \(grams) g of carbs \(minutes) min ago and no bolus is recorded. If you dosed, log it — if not, this is your nudge.")
        case .risingUnlogged:
            content.title = String(localized: "Rising fast — nothing logged")
            content.body = String(localized: "Glucose climbed quickly in the last hour with no meal or bolus logged. If you ate, log it and consider your dose.")
        }
        content.sound = AlertSoundStore.load().important.notificationSound
        content.relevanceScore = 0.7
        let request = UNNotificationRequest(
            identifier: "glucose-missed-bolus-\(alert.kind.rawValue)",
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
        // An imminent low is lead time for a hypo — critical treatment.
        content.sound = AlertSoundStore.load().critical.notificationSound
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
