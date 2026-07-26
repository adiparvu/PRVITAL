import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules the Sunday-evening "insight of the week" notification (Sunday
/// 19:00 local time), carrying the current top insight's *headline* — the
/// pattern ("Often low overnight"), never a number — as its body.
///
/// Local notifications are static once scheduled, so the body is refreshed by
/// `AppEnvironment.rearmWeeklyInsight()` on every launch and activation: as
/// long as the user opens the app now and then, Sunday's notification carries
/// this week's pattern. Opt-in, computed entirely on device, and owner of its
/// own identifier prefix so it can't disturb reminders or the Monday digest
/// invite. Like the digest, it must be re-armed after
/// `NotificationScheduler.reschedule` clears all pending requests.
@MainActor
final class WeeklyInsightScheduler {

    /// Identifier prefix owned by this scheduler.
    static let identifierPrefix = "weekly-insight"
    /// The single repeating Sunday-evening request.
    static let identifier = identifierPrefix + "-sunday"

    #if canImport(UserNotifications)
    private let center = UNUserNotificationCenter.current()
    #endif

    /// Schedules the Sunday 19:00 notification when `enabled`, cancels it when
    /// not. Idempotent: the stable identifier makes a re-add replace, never
    /// stack. Authorization is requested by the enabling UI; the system simply
    /// drops scheduled notifications when permission isn't granted.
    func update(enabled: Bool, topInsightTitle: String?) {
        #if canImport(UserNotifications)
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Insight of the week")
        content.body = topInsightTitle
            ?? String(localized: "See what stood out in your glucose this week.")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1   // Sunday (Gregorian weekday: 1 = Sunday)
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
        #endif
    }

    /// Re-arms from the persisted preference with a generic body, for callers
    /// that just cleared every pending request and can't compute the feed; the
    /// next app activation swaps in the live headline. The key literal must
    /// match `Preferences.Keys.weeklyInsight`.
    static func restoreFromDefaults() {
        let enabled = UserDefaults(suiteName: SharedStore.appGroupIdentifier)?
            .bool(forKey: "pref.weeklyInsightEnabled") ?? false
        WeeklyInsightScheduler().update(enabled: enabled, topInsightTitle: nil)
    }
}
