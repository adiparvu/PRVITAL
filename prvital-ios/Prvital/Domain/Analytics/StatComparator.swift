import Foundation

/// The change in the headline glucose metrics between the current period and the
/// equal-length period immediately before it. Positive `timeInRangeDelta` means
/// more time in range than last period (an improvement); `averageDelta` is the
/// change in mean glucose in mg/dL (direction is neutral — lower is not always
/// better).
struct StatComparison: Equatable, Sendable {
    /// Change in time-in-range fraction (current − previous), in 0…1 points.
    var timeInRangeDelta: Double
    /// Change in mean glucose (current − previous), in mg/dL.
    var averageDelta: Double
    /// Whether there was a comparable previous period with glucose data.
    var hasPrevious: Bool
}

/// Pure comparison of two `PeriodStatistics`. Deterministic and side-effect free,
/// so the "vs previous period" card is trivially testable.
enum StatComparator {
    static func compare(current: PeriodStatistics, previous: PeriodStatistics?) -> StatComparison {
        guard let previous, previous.hasGlucose else {
            return StatComparison(timeInRangeDelta: 0, averageDelta: 0, hasPrevious: false)
        }
        return StatComparison(
            timeInRangeDelta: current.timeInRange - previous.timeInRange,
            averageDelta: current.average - previous.average,
            hasPrevious: true
        )
    }
}
