import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Expiry countdown notifications for the current sensor wear: two days out,
/// the day before, and at the expiry itself. Rescheduled whenever a session
/// starts (manually or via the auto-tracker), replacing the previous set —
/// there is only ever one current sensor.
enum SensorExpiryScheduler {
    private static let identifiers = [
        "sensor.expiry.48h", "sensor.expiry.24h", "sensor.expiry.now",
    ]

    static func reschedule(expiryDate: Date, sensorName: String, now: Date = Date()) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let steps: [(id: String, at: Date, body: String)] = [
            ("sensor.expiry.48h", expiryDate.addingTimeInterval(-48 * 3600),
             String(localized: "Your \(sensorName) expires in 2 days. A good moment to check you have the next one.")),
            ("sensor.expiry.24h", expiryDate.addingTimeInterval(-24 * 3600),
             String(localized: "Your \(sensorName) expires tomorrow.")),
            ("sensor.expiry.now", expiryDate,
             String(localized: "Your \(sensorName) has reached the end of its wear time. Replace it to keep readings coming.")),
        ]
        for step in steps where step.at > now {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Sensor change")
            content.body = step.body
            content.sound = .default
            content.relevanceScore = 0.6
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: step.at.timeIntervalSince(now), repeats: false)
            center.add(UNNotificationRequest(identifier: step.id, content: content, trigger: trigger))
        }
        #endif
    }
}
