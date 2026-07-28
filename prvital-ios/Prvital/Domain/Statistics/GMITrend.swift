import Foundation

/// One week's estimated A1c (Glucose Management Indicator) point for the trend.
struct GMIPoint: Identifiable, Sendable {
    let weekStart: Date
    let gmi: Double
    let readingCount: Int

    var id: Date { weekStart }
}

/// Builds a weekly estimated-A1c (GMI) series from a CGM trace, so progress over
/// time is visible. Pure and deterministic given a calendar: it buckets active
/// readings by week, and for each week with enough data computes the GMI from
/// the mean glucose (the same 3.31 + 0.02392·mean formula the StatisticsEngine
/// uses).
enum GMITrend {
    static let defaultMinReadingsPerWeek = 1

    static func weekly(
        _ readings: [GlucoseReading],
        calendar: Calendar = .current,
        minReadingsPerWeek: Int = defaultMinReadingsPerWeek
    ) -> [GMIPoint] {
        let active = readings.filter { $0.isActive }
        guard !active.isEmpty else { return [] }

        var byWeek: [Date: [Double]] = [:]
        for reading in active {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: reading.timestamp)?.start
                ?? calendar.startOfDay(for: reading.timestamp)
            byWeek[weekStart, default: []].append(reading.valueMgdL)
        }

        return byWeek
            .filter { $0.value.count >= minReadingsPerWeek }
            .map { weekStart, values in
                let mean = values.reduce(0, +) / Double(values.count)
                return GMIPoint(weekStart: weekStart, gmi: 3.31 + 0.02392 * mean, readingCount: values.count)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }
}
