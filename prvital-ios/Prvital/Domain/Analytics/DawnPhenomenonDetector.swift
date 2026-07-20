import Foundation

/// The result of scanning for the **dawn phenomenon** — a recurring rise in
/// glucose from the overnight low into the early morning, driven by circadian
/// hormone release. Quantified as the median day-over-day rise from the
/// pre-dawn nadir to the pre-breakfast morning level.
struct DawnPhenomenonResult: Equatable, Sendable {
    /// Days that had readings in both the nadir and morning windows.
    let dayCount: Int
    /// Median rise (mg/dL) from the overnight nadir to the morning level.
    let medianRiseMgdL: Double
    /// Whether the pattern is present often and strongly enough to surface.
    var isPresent: Bool
}

/// Detects the dawn phenomenon from a CGM trace. Pure and deterministic: it
/// buckets readings by local calendar day, and for each day compares the
/// overnight nadir with the pre-breakfast morning level. A day only counts when
/// it has readings in both windows, so partial nights never fabricate a rise.
enum DawnPhenomenonDetector {
    /// Minimum qualifying days before the pattern is considered real.
    static let minDays = 3
    /// A median morning rise at or above this (mg/dL) is clinically notable.
    static let riseThresholdMgdL: Double = 20
    /// Local hours [0, 6) searched for the overnight nadir.
    static let nadirHours = 0..<6
    /// Local hours [6, 9) averaged for the pre-breakfast morning level.
    static let morningHours = 6..<9

    static func analyze(_ readings: [GlucoseReading], calendar: Calendar = .current) -> DawnPhenomenonResult? {
        let active = readings.filter { $0.isActive }
        guard !active.isEmpty else { return nil }

        var byDay: [Date: [GlucoseReading]] = [:]
        for reading in active {
            let day = calendar.startOfDay(for: reading.timestamp)
            byDay[day, default: []].append(reading)
        }

        var rises: [Double] = []
        for (_, dayReadings) in byDay {
            let nadirValues = dayReadings
                .filter { nadirHours.contains(calendar.component(.hour, from: $0.timestamp)) }
                .map(\.valueMgdL)
            let morningValues = dayReadings
                .filter { morningHours.contains(calendar.component(.hour, from: $0.timestamp)) }
                .map(\.valueMgdL)
            guard let nadir = nadirValues.min(), !morningValues.isEmpty else { continue }
            let morning = morningValues.reduce(0, +) / Double(morningValues.count)
            rises.append(morning - nadir)
        }

        guard !rises.isEmpty else { return nil }
        let median = Self.median(rises)
        let present = rises.count >= minDays && median >= riseThresholdMgdL
        return DawnPhenomenonResult(dayCount: rises.count, medianRiseMgdL: median, isPresent: present)
    }

    /// Median of a non-empty list (mean of the two middle values when even).
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
