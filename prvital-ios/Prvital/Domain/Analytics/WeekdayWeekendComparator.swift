import Foundation

/// Time-in-range and average glucose split by weekday vs weekend — routines,
/// meals and activity often differ at the weekend, and this makes that visible.
struct DayTypeStats: Equatable, Sendable {
    let weekdayTimeInRange: Double
    let weekendTimeInRange: Double
    let weekdayAverageMgdL: Double
    let weekendAverageMgdL: Double
}

/// Splits a CGM trace into weekday and weekend buckets (per the calendar's own
/// weekend definition) and summarises each with the shared `StatisticsEngine`.
/// Pure and deterministic given a calendar, so it is fully unit-testable.
enum WeekdayWeekendComparator {
    /// Returns the split stats, or nil unless *both* buckets contain glucose
    /// (a one-sided comparison would be misleading).
    static func compare(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current
    ) -> DayTypeStats? {
        let active = readings.filter { $0.isActive }
        let weekend = active.filter { calendar.isDateInWeekend($0.timestamp) }
        let weekday = active.filter { !calendar.isDateInWeekend($0.timestamp) }
        guard !weekend.isEmpty, !weekday.isEmpty else { return nil }

        let weekdayStats = StatisticsEngine.glucose(weekday, thresholds: thresholds)
        let weekendStats = StatisticsEngine.glucose(weekend, thresholds: thresholds)
        return DayTypeStats(
            weekdayTimeInRange: weekdayStats.timeInRange,
            weekendTimeInRange: weekendStats.timeInRange,
            weekdayAverageMgdL: weekdayStats.average,
            weekendAverageMgdL: weekendStats.average
        )
    }
}
