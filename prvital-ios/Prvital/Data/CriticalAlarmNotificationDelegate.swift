import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The app's `UNUserNotificationCenterDelegate`. Its only job today is
/// acknowledging the critical-low escalation: when the user taps the
/// "I'm on it" action — or simply opens the urgent-low alert or one of its
/// repeats — every scheduled repeat is stood down.
///
/// Installed once from `PrvitalApp.init`, before the app finishes launching,
/// so a response that launches the app is not missed. Intentionally stateless:
/// response handling only touches thread-safe system objects, so the callback
/// is `nonisolated` and does its work synchronously.
final class CriticalAlarmNotificationDelegate: NSObject {
    @MainActor static let shared = CriticalAlarmNotificationDelegate()

    /// Makes this object the notification center's delegate (the center only
    /// holds it weakly; `shared` keeps it alive).
    @MainActor static func install() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = shared
        #endif
    }
}

#if canImport(UserNotifications)
extension CriticalAlarmNotificationDelegate: UNUserNotificationCenterDelegate {
    /// Acknowledges on the explicit "I'm on it" action, or on a default tap of
    /// the urgent-low alert / any critical repeat. Dismissing a notification is
    /// deliberately *not* an acknowledgment — swiping a banner away should not
    /// silence a safety escalation.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        if action == CriticalAlarmPlanner.acknowledgeActionIdentifier
            || (action == UNNotificationDefaultActionIdentifier
                && CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: identifier)) {
            CriticalAlarmScheduler.standDown()
        }
        completionHandler()
    }

    // `userNotificationCenter(_:willPresent:withCompletionHandler:)` is
    // intentionally not implemented: foreground presentation keeps the system
    // default, matching the app's behavior before this delegate existed.
}
#endif
