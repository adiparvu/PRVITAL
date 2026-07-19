import Foundation

/// A computed statistics summary for a period. All glucose figures are mg/dL.
struct PeriodStatistics: Equatable, Sendable {
    var readingCount: Int = 0
    var average: Double = 0
    var minimum: Double = 0
    var maximum: Double = 0
    var standardDeviation: Double = 0
    /// Coefficient of variation (SD / mean), the standard glucose-variability metric.
    var coefficientOfVariation: Double = 0
    /// Glucose Management Indicator, an estimated A1c (%) derived from the mean.
    var glucoseManagementIndicator: Double = 0

    // Fractions in 0...1 across the target bands.
    var timeInRange: Double = 0
    var timeAboveRange: Double = 0
    var timeBelowRange: Double = 0
    var timeVeryLow: Double = 0
    var timeVeryHigh: Double = 0
    /// Fraction in the tighter 70–140 mg/dL consensus "tight" range (TITR).
    var timeInTightRange: Double = 0

    /// Distinct excursion events (contiguous runs out of range), not raw counts.
    var hypoEvents: Int = 0
    var hyperEvents: Int = 0

    // Therapy & intake totals.
    var totalBolusUnits: Double = 0
    var totalBasalUnits: Double = 0
    var totalCarbGrams: Double = 0
    var mealCount: Int = 0
    var activityMinutes: Int = 0

    var hasGlucose: Bool { readingCount > 0 }
}

/// Pure functions that turn record collections into a `PeriodStatistics`.
///
/// Time-in-range is computed as the proportion of readings in each band — the
/// correct estimator when readings are evenly sampled, as CGM data is. Excursion
/// **events** are counted by walking the time-ordered series and detecting each
/// contiguous run that leaves the target range, so a two-hour low counts once.
enum StatisticsEngine {

    /// Lower bound (mg/dL) of the consensus "tight" range for TITR.
    static let tightRangeLowerMgdL: Double = 70
    /// Upper bound (mg/dL) of the consensus "tight" range for TITR.
    static let tightRangeUpperMgdL: Double = 140

    static func glucose(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds
    ) -> PeriodStatistics {
        var stats = PeriodStatistics()
        let active = readings.filter(\.isActive)
        guard !active.isEmpty else { return stats }

        let values = active.map(\.valueMgdL)
        let n = Double(values.count)
        stats.readingCount = values.count
        stats.average = values.reduce(0, +) / n
        stats.minimum = values.min() ?? 0
        stats.maximum = values.max() ?? 0

        let variance = values.reduce(0) { $0 + pow($1 - stats.average, 2) } / n
        stats.standardDeviation = variance.squareRoot()
        stats.coefficientOfVariation = stats.average > 0
            ? stats.standardDeviation / stats.average : 0
        stats.glucoseManagementIndicator = 3.31 + 0.02392 * stats.average

        // Banded time fractions.
        var inRange = 0, below = 0, above = 0, veryLow = 0, veryHigh = 0
        for v in values {
            switch thresholds.zone(forMgdL: v) {
            case .veryLow: below += 1; veryLow += 1
            case .low: below += 1
            case .inRange: inRange += 1
            case .high: above += 1
            case .veryHigh: above += 1; veryHigh += 1
            }
        }
        stats.timeInRange = Double(inRange) / n
        stats.timeBelowRange = Double(below) / n
        stats.timeAboveRange = Double(above) / n
        stats.timeVeryLow = Double(veryLow) / n
        stats.timeVeryHigh = Double(veryHigh) / n

        let inTight = values.filter { $0 >= tightRangeLowerMgdL && $0 <= tightRangeUpperMgdL }.count
        stats.timeInTightRange = Double(inTight) / n

        // Excursion events over the time-ordered series.
        let ordered = active.sorted { $0.timestamp < $1.timestamp }
        stats.hypoEvents = countEvents(ordered, thresholds: thresholds) { $0.isHypo }
        stats.hyperEvents = countEvents(ordered, thresholds: thresholds) { $0.isHyper }
        return stats
    }

    /// Folds therapy / intake / activity totals into an existing summary.
    static func enrich(
        _ base: PeriodStatistics,
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry]
    ) -> PeriodStatistics {
        var stats = base
        for dose in insulin {
            if dose.insulinType.isBasal { stats.totalBasalUnits += dose.units }
            else { stats.totalBolusUnits += dose.units }
        }
        stats.totalCarbGrams = carbs.reduce(0) { $0 + $1.grams }
        stats.mealCount = carbs.count
        stats.activityMinutes = activity.reduce(0) { $0 + $1.durationMinutes }
        return stats
    }

    private static func countEvents(
        _ ordered: [GlucoseReading],
        thresholds: GlucoseThresholds,
        matching predicate: (GlucoseZone) -> Bool
    ) -> Int {
        var events = 0
        var inEvent = false
        for reading in ordered {
            let hit = predicate(thresholds.zone(forMgdL: reading.valueMgdL))
            if hit && !inEvent { events += 1; inEvent = true }
            else if !hit { inEvent = false }
        }
        return events
    }
}
