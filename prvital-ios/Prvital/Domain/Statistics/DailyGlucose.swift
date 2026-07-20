import Foundation

/// Convenience for "today" summaries on the Dashboard. Pure and deterministic
/// given a reference date and calendar, so the day-boundary filtering is
/// unit-testable independently of the shared `StatisticsEngine`.
enum DailyGlucose {
    /// Statistics for the readings that fall on the same calendar day as
    /// `reference` (its local midnight up to, but not including, the next).
    static func today(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> PeriodStatistics {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? reference
        let todays = readings.filter { $0.timestamp >= start && $0.timestamp < end }
        return StatisticsEngine.glucose(todays, thresholds: thresholds)
    }
}
