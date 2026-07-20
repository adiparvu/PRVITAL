import Foundation

/// One week's time-in-range point for the trend.
struct TIRPoint: Identifiable {
    let weekStart: Date
    let timeInRange: Double
    let readingCount: Int

    var id: Date { weekStart }
}

/// Builds a weekly time-in-range series from a CGM trace, so the headline
/// diabetes metric's trajectory is visible. Pure and deterministic given a
/// calendar: it buckets active readings by week and summarises each week with
/// the shared `StatisticsEngine`, keeping only weeks with enough data.
enum TIRTrend {
    static let defaultMinReadingsPerWeek = 1

    static func weekly(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current,
        minReadingsPerWeek: Int = defaultMinReadingsPerWeek
    ) -> [TIRPoint] {
        let active = readings.filter { $0.isActive }
        guard !active.isEmpty else { return [] }

        var byWeek: [Date: [GlucoseReading]] = [:]
        for reading in active {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: reading.timestamp)?.start
                ?? calendar.startOfDay(for: reading.timestamp)
            byWeek[weekStart, default: []].append(reading)
        }

        return byWeek
            .filter { $0.value.count >= minReadingsPerWeek }
            .map { weekStart, weekReadings in
                let stats = StatisticsEngine.glucose(weekReadings, thresholds: thresholds)
                return TIRPoint(weekStart: weekStart, timeInRange: stats.timeInRange, readingCount: stats.readingCount)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }
}
