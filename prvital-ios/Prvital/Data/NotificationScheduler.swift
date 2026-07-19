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
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    #endif

    /// Clears existing reminders and reschedules from the current preferences.
    func reschedule(from reminders: ReminderPreferences) {
        #if canImport(UserNotifications)
        center.removeAllPendingNotificationRequests()
        var requests: [UNNotificationRequest] = []

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

        for request in requests { center.add(request) }
        #endif
    }

    #if canImport(UserNotifications)
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
