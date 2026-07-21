import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules the Monday-morning "week in review" invitation as a repeating local
/// notification (Monday 09:00 local time).
///
/// The notification is a static invite — it never carries a medical value; the
/// app composes the actual digest (`WeeklyDigest`) on demand when the user opens
/// it. Kept separate from `NotificationScheduler` with its own identifier
/// prefix, so digest scheduling can't disturb the user's reminders and vice
/// versa. Note that `NotificationScheduler.reschedule` clears *all* pending
/// requests, so `update(enabled:)` must be re-run after any full reminder
/// reschedule (see `AppEnvironment.bootstrap`).
@MainActor
final class WeeklyDigestScheduler {

    /// Identifier prefix owned by this scheduler.
    static let identifierPrefix = "weekly-digest"
    /// The single repeating Monday-morning request.
    static let identifier = identifierPrefix + "-monday"

    #if canImport(UserNotifications)
    private let center = UNUserNotificationCenter.current()
    #endif

    /// Schedules the Monday 09:00 invitation when `enabled`, cancels it when
    /// not. Idempotent: the stable identifier makes a re-add replace, never
    /// stack. Authorization is requested by the enabling UI; the system simply
    /// drops scheduled notifications when permission isn't granted.
    func update(enabled: Bool) {
        #if canImport(UserNotifications)
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your week in review is ready")
        content.body = String(localized: "See last week's time in range, best day and more.")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 2   // Monday (Gregorian weekday: 1 = Sunday)
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
        #endif
    }

    /// Re-arms the Monday invitation from the persisted preference, for callers
    /// that just cleared every pending request (`NotificationScheduler.reschedule`)
    /// and don't hold a `Preferences` instance. The key literal must match
    /// `Preferences.Keys.weeklyDigest`.
    static func restoreFromDefaults() {
        let enabled = UserDefaults(suiteName: SharedStore.appGroupIdentifier)?
            .bool(forKey: "pref.weeklyDigestEnabled") ?? false
        WeeklyDigestScheduler().update(enabled: enabled)
    }
}
