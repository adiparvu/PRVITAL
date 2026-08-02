import Foundation
import SwiftData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The wake-up note: "Overnight: 92% in range, low of 82 at 3:40, no alarms."
///
/// Notification content must exist BEFORE it fires, so the rich text can't be a
/// simple daily trigger — the night's numbers don't exist at scheduling time.
/// Every sync/refresh between 04:00 and the chosen delivery time recomputes the
/// night so far (00:00 → now) and (re)schedules today's notification with the
/// freshest numbers; background refresh runs on roughly the CGM cadence, so the
/// delivered text is at most a few minutes stale.
///
/// iOS never guarantees a background wake, though — so a plain "see how your
/// night went" copy is also queued for today and the next six mornings as a
/// safety net. Any morning the app does wake, the rich text replaces today's
/// plain one (same identifier); any morning it doesn't, the report still
/// arrives and opening the app shows the night.
@ModelActor
actor MorningReportScheduler {
    static let notificationIdentifier = "prvital.morningReport"
    /// The safety-net copies for the following six mornings.
    static let aheadIdentifiers = (1...6).map { "prvital.morningReport.ahead.\($0)" }

    func update(enabled: Bool, minutesFromMidnight: Int, unit: GlucoseUnit,
                thresholds: GlucoseThresholds, now: Date = Date()) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier] + Self.aheadIdentifiers)
        guard enabled else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let fireDate = dayStart.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))

        func schedule(identifier: String, day: Date, body: String) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Good morning")
            content.body = body
            content.sound = nil   // a report, not an alarm
            content.relevanceScore = 0.4
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = minutesFromMidnight / 60
            comps.minute = minutesFromMidnight % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        let plainBody = String(localized: "Morning report: see how your night went.")
        if now < fireDate {
            schedule(identifier: Self.notificationIdentifier, day: dayStart, body: plainBody)
        }
        for (index, identifier) in Self.aheadIdentifiers.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: index + 1, to: dayStart)
            else { continue }
            schedule(identifier: identifier, day: day, body: plainBody)
        }

        // The rich copy for today, when the night's data exists and the delivery
        // time is still ahead — replaces the plain one under the same identifier.
        let windowStart = dayStart.addingTimeInterval(4 * 3600)
        guard now >= windowStart, now < fireDate else { return }

        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= dayStart && $0.timestamp <= now },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        guard readings.count >= 12 else { return }

        let stats = StatisticsEngine.glucose(readings, thresholds: thresholds)
        let lowest = readings.min { $0.valueMgdL < $1.valueMgdL }

        let tir = Int((stats.timeInRange * 100).rounded())
        let body: String
        if let lowest {
            let lowText = GlucoseFormatting.labeled(mgdL: lowest.valueMgdL, unit: unit)
            let time = lowest.timestamp.formatted(date: .omitted, time: .shortened)
            if stats.hypoEvents == 0 {
                body = String(localized: "Overnight: \(tir)% in range, lowest \(lowText) at \(time), no lows.")
            } else {
                body = String(localized: "Overnight: \(tir)% in range, lowest \(lowText) at \(time). Worth a glance at the chart.")
            }
        } else {
            body = String(localized: "Overnight: \(tir)% in range.")
        }
        schedule(identifier: Self.notificationIdentifier, day: dayStart, body: body)
        #endif
    }
}
