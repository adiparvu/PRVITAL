import Foundation
import SwiftData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The wake-up note: "Overnight: 92% in range, low of 82 at 3:40, no alarms."
///
/// Notification content must exist BEFORE it fires, so this can't be a simple
/// daily trigger — the night's numbers don't exist at scheduling time. Instead,
/// every sync/refresh between 04:00 and the chosen delivery time recomputes the
/// night so far (00:00 → now) and (re)schedules today's notification with the
/// freshest numbers; background refresh runs on roughly the CGM cadence, so the
/// delivered text is at most a few minutes stale. Outside that window it
/// removes any leftover pending copy. No data overnight → no notification.
@ModelActor
actor MorningReportScheduler {
    static let notificationIdentifier = "prvital.morningReport"

    func update(enabled: Bool, minutesFromMidnight: Int, unit: GlucoseUnit,
                thresholds: GlucoseThresholds, now: Date = Date()) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        guard enabled else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let fireDate = dayStart.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
        let windowStart = dayStart.addingTimeInterval(4 * 3600)
        guard now >= windowStart, now < fireDate else { return }

        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= dayStart && $0.timestamp <= now },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        guard readings.count >= 12 else { return }

        let stats = StatisticsEngine.glucose(readings, thresholds: thresholds)
        let lowest = readings.min { $0.valueMgdL < $1.valueMgdL }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Good morning")
        let tir = Int((stats.timeInRange * 100).rounded())
        if let lowest {
            let lowText = GlucoseFormatting.labeled(mgdL: lowest.valueMgdL, unit: unit)
            let time = lowest.timestamp.formatted(date: .omitted, time: .shortened)
            if stats.hypoEvents == 0 {
                content.body = String(localized: "Overnight: \(tir)% in range, lowest \(lowText) at \(time), no lows.")
            } else {
                content.body = String(localized: "Overnight: \(tir)% in range, lowest \(lowText) at \(time). Worth a glance at the chart.")
            }
        } else {
            content.body = String(localized: "Overnight: \(tir)% in range.")
        }
        content.sound = nil   // a report, not an alarm
        content.relevanceScore = 0.4

        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(
            identifier: Self.notificationIdentifier, content: content, trigger: trigger))
        #endif
    }
}
