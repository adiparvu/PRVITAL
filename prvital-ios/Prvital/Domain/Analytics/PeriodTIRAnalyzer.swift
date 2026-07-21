import Foundation

/// Time-in-Range for one part of the day, measured against that period's target.
struct PeriodTIR: Identifiable, Equatable, Sendable {
    let period: DayPeriod
    /// Time-in-Range for the period (0…1).
    let timeInRange: Double
    let readingCount: Int
    /// The effective target for this period (0…1) — per-period or the global goal.
    let targetFraction: Double

    var id: String { period.rawValue }
    var hasData: Bool { readingCount > 0 }
    var met: Bool { hasData && timeInRange >= targetFraction }
}

/// Splits readings into the four `DayPeriod` windows and measures Time-in-Range
/// in each against its (possibly period-specific) target. Pure and deterministic.
enum PeriodTIRAnalyzer {
    static func breakdown(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        targets: PeriodTIRTargets,
        globalTargetPercent: Double,
        calendar: Calendar = .current
    ) -> [PeriodTIR] {
        let active = readings.filter(\.isActive)
        return DayPeriod.allCases.map { period in
            let inPeriod = active.filter { period.contains($0.timestamp, calendar: calendar) }
            let tir = StatisticsEngine.glucose(inPeriod, thresholds: thresholds).timeInRange
            return PeriodTIR(
                period: period,
                timeInRange: tir,
                readingCount: inPeriod.count,
                targetFraction: targets.targetFraction(for: period, global: globalTargetPercent))
        }
    }
}
