import Foundation

/// Per-day roll-up for the calendar grid.
struct DaySummary: Identifiable {
    var date: Date            // start of day
    var averageMgdL: Double
    var readingCount: Int
    var entryCount: Int       // all record types combined
    var timeInRange: Double
    var zone: GlucoseZone     // colour of the day, from the day's average

    var id: Date { date }
    var hasData: Bool { entryCount > 0 }
}

/// Buckets records into calendar days and colours each day by its mean glucose.
enum CalendarAggregator {
    static func summaries(
        readings: [GlucoseReading],
        insulin: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        activity: [ActivityEntry] = [],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current
    ) -> [Date: DaySummary] {
        var byDay: [Date: [GlucoseReading]] = [:]
        for reading in readings where reading.isActive {
            let day = calendar.startOfDay(for: reading.timestamp)
            byDay[day, default: []].append(reading)
        }

        // Entry counts across all record types.
        var entryCounts: [Date: Int] = [:]
        func bump(_ date: Date) { entryCounts[calendar.startOfDay(for: date), default: 0] += 1 }
        readings.filter(\.isActive).forEach { bump($0.timestamp) }
        insulin.forEach { bump($0.timestamp) }
        carbs.forEach { bump($0.timestamp) }
        activity.forEach { bump($0.startTimestamp) }

        var result: [Date: DaySummary] = [:]
        let days = Set(byDay.keys).union(entryCounts.keys)
        for day in days {
            let dayReadings = byDay[day] ?? []
            let values = dayReadings.map(\.valueMgdL)
            let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            let inRange = values.filter { thresholds.inRange($0) }.count
            let tir = values.isEmpty ? 0 : Double(inRange) / Double(values.count)
            result[day] = DaySummary(
                date: day,
                averageMgdL: avg,
                readingCount: values.count,
                entryCount: entryCounts[day] ?? 0,
                timeInRange: tir,
                zone: values.isEmpty ? .inRange : thresholds.zone(forMgdL: avg)
            )
        }
        return result
    }
}
