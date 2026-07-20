import Foundation

/// One day's time-in-range, used to surface the best and toughest days.
struct DayTIR: Identifiable {
    let day: Date
    let timeInRange: Double
    let readingCount: Int

    var id: Date { day }
}

/// Breaks a CGM trace into per-day time-in-range. Pure and deterministic given a
/// calendar: readings are bucketed by local day and each day is summarised with
/// the shared `StatisticsEngine`. Days below the minimum reading count are
/// dropped so a single stray reading can't masquerade as a "best day".
enum DailyBreakdown {
    static let defaultMinReadingsPerDay = 6

    static func perDay(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current,
        minReadingsPerDay: Int = defaultMinReadingsPerDay
    ) -> [DayTIR] {
        let active = readings.filter { $0.isActive }
        guard !active.isEmpty else { return [] }

        var byDay: [Date: [GlucoseReading]] = [:]
        for reading in active {
            byDay[calendar.startOfDay(for: reading.timestamp), default: []].append(reading)
        }

        return byDay
            .filter { $0.value.count >= minReadingsPerDay }
            .map { day, dayReadings in
                let stats = StatisticsEngine.glucose(dayReadings, thresholds: thresholds)
                return DayTIR(day: day, timeInRange: stats.timeInRange, readingCount: stats.readingCount)
            }
            .sorted { $0.day < $1.day }
    }

    /// The day with the highest time-in-range.
    static func best(_ days: [DayTIR]) -> DayTIR? {
        days.max { $0.timeInRange < $1.timeInRange }
    }

    /// The day with the lowest time-in-range.
    static func worst(_ days: [DayTIR]) -> DayTIR? {
        days.min { $0.timeInRange < $1.timeInRange }
    }
}
