import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules the user's configured local reminders (journal, basal insulin,
/// meals, hydration, glucose checks). All notifications are local and repeat
/// daily; none carry medical values.
@MainActor
final class NotificationScheduler {
    #if canImport(UserNotifications)
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        Self.registerNotificationCategories()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    #endif

    /// Registers the app's actionable notification categories. Today that is
    /// just the critical-alarm category, whose "I'm on it" action acknowledges
    /// the repeat-until-acknowledged urgent-low escalation.
    /// `setNotificationCategories` replaces the entire set, so this must stay
    /// the single place categories are defined. Safe to call repeatedly.
    static func registerNotificationCategories() {
        #if canImport(UserNotifications)
        let acknowledge = UNNotificationAction(
            identifier: CriticalAlarmPlanner.acknowledgeActionIdentifier,
            title: String(localized: "I'm on it"),
            options: [])
        let critical = UNNotificationCategory(
            identifier: CriticalAlarmPlanner.categoryIdentifier,
            actions: [acknowledge],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([critical])
        #endif
    }

    /// Clears existing reminders and reschedules from the current preferences.
    func reschedule(from reminders: ReminderPreferences, glucoseSchedule: GlucoseSchedule = .default,
                    medicationPlan: MedicationPlan = .empty) {
        #if canImport(UserNotifications)
        center.removeAllPendingNotificationRequests()
        var requests: [UNNotificationRequest] = []

        if glucoseSchedule.remindersEnabled {
            for slot in glucoseSchedule.activeSlots {
                requests.append(daily("Log your glucose", "Time for your \(slot.label.lowercased()) reading.",
                                      slot.minutesFromMidnight, "glucoseslot-\(slot.id.uuidString)"))
            }
        }

        if reminders.journalEnabled {
            for minute in reminders.journalTimes {
                requests.append(daily("Update your journal", "A good moment to log how you're doing.", minute, "journal"))
            }
        }
        if reminders.basalEnabled {
            requests.append(daily("Basal insulin", "Time for your long-acting dose.", reminders.basalTime, "basal"))
        }
        if reminders.mealsEnabled {
            for minute in reminders.mealTimes {
                requests.append(daily("Mealtime", "Log carbs and any bolus.", minute, "meal"))
            }
        }
        if reminders.glucoseCheckEnabled {
            for minute in reminders.glucoseCheckTimes {
                requests.append(daily("Check your glucose", "A quick reading keeps your trend complete.", minute, "glucose"))
            }
        }
        if reminders.hydrationEnabled {
            requests.append(interval("Stay hydrated", "Have some water.",
                                     hours: reminders.hydrationIntervalHours, "hydration"))
        }

        // Medication reminders — one daily notification per scheduled time. The
        // med name is dynamic, so the title/body are localized here (content()
        // re-localizing an already-resolved string is a harmless no-op).
        for schedule in medicationPlan.activeSchedules where schedule.remindersEnabled && !schedule.name.isEmpty {
            let title = String(localized: "Take \(schedule.name)")
            let body = (schedule.doseText.isEmpty || schedule.doseText == schedule.name)
                ? String(localized: "Time for your medication.")
                : String(localized: "Time for your \(schedule.doseText) dose.")
            for minute in schedule.sortedTimes {
                requests.append(daily(title, body, minute, "med-\(schedule.id.uuidString)"))
            }
        }

        for request in requests { center.add(request) }

        // The wholesale clear above also drops any armed critical-low repeat
        // notifications; rebuild the ones still due from their persisted
        // anchor so a settings change can never silently disarm the alarm.
        CriticalAlarmScheduler.restorePendingRepeats()
        // Same for the Monday "week in review" invitation.
        WeeklyDigestScheduler.restoreFromDefaults()
        #endif
    }

    // MARK: Contextual (data-driven) reminders

    /// Shared identifier prefix for every contextual reminder, so a reschedule can
    /// cancel the previous batch without touching the fixed-clock reminders above.
    static let contextualIdentifierPrefix = "contextual-"

    static func contextualIdentifier(for kind: ContextualReminderKind) -> String {
        contextualIdentifierPrefix + kind.rawValue
    }

    /// Cancels the previous contextual reminders (every stable identifier under the
    /// shared prefix) and schedules the currently-due ones. Safe to call on every
    /// data change: identifiers are stable per kind, so a reminder replaces rather
    /// than stacks, and a kind absent from `reminders` is simply cancelled — which
    /// is how a nudge that's no longer warranted (e.g. once a bolus is logged) goes
    /// away. Authorization is handled by `requestAuthorization()`; the system drops
    /// scheduled notifications when permission isn't granted.
    func rescheduleContextual(_ reminders: [ContextualReminder]) {
        #if canImport(UserNotifications)
        let staleIdentifiers = ContextualReminderKind.allCases.map(Self.contextualIdentifier(for:))
        center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

        for reminder in reminders {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, reminder.fireDelay), repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.contextualIdentifier(for: reminder.kind),
                content: contextualContent(reminder),
                trigger: trigger)
            center.add(request)
        }
        #endif
    }

    #if canImport(UserNotifications)
    private func contextualContent(_ reminder: ContextualReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // The evaluator already returns localized, presentation-ready strings.
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.relevanceScore = 0.5
        return content
    }

    private func daily(_ title: String, _ body: String, _ minutesFromMidnight: Int, _ prefix: String) -> UNNotificationRequest {
        var components = DateComponents()
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: "\(prefix)-\(minutesFromMidnight)", content: content(title, body), trigger: trigger)
    }

    private func interval(_ title: String, _ body: String, hours: Int, _ id: String) -> UNNotificationRequest {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, hours) * 3600), repeats: true)
        return UNNotificationRequest(identifier: id, content: content(title, body), trigger: trigger)
    }

    private func content(_ title: String, _ body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // The call sites pass the English strings, which double as catalog keys.
        content.title = String(localized: String.LocalizationValue(stringLiteral: title))
        content.body = String(localized: String.LocalizationValue(stringLiteral: body))
        content.sound = .default
        return content
    }
    #endif
}
