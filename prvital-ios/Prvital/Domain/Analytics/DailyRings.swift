import Foundation

/// The three daily "rings" shown on the Dashboard and the Daily goals screen, in
/// the spirit of Apple's activity rings but tuned for diabetes self-management:
///
///   • **In range** — today's Time-in-Range against the user's TIR goal.
///   • **Active**    — today's logged activity minutes against a movement goal.
///   • **Sensor**    — CGM data coverage of the elapsed day (sensor uptime).
///
/// Pure and deterministic: it takes the already-fetched records plus the goals
/// and a reference `now`, and computes fractions only. All formatting, colours
/// and localization live in the view, so this stays trivially testable.
struct DailyRings: Equatable, Sendable {
    /// Today's Time-in-Range as a 0…1 fraction, and the goal fraction it targets.
    var inRangeFraction: Double
    var inRangeGoalFraction: Double

    /// Minutes of logged activity today, and the daily movement goal.
    var activeMinutes: Int
    var activeGoalMinutes: Int

    /// CGM coverage of the elapsed part of today (0…1), and the uptime goal.
    var coverageFraction: Double
    var coverageGoalFraction: Double

    /// Whether any glucose was recorded today (drives the empty state).
    var hasGlucose: Bool

    // MARK: Progress (each clamped to 0…1 = "goal reached")

    var inRangeProgress: Double { fraction(inRangeFraction, of: inRangeGoalFraction) }
    var activeProgress: Double { fraction(Double(activeMinutes), of: Double(activeGoalMinutes)) }
    var coverageProgress: Double { fraction(coverageFraction, of: coverageGoalFraction) }

    var inRangeMet: Bool { inRangeProgress >= 1 }
    var activeMet: Bool { activeProgress >= 1 }
    var coverageMet: Bool { coverageProgress >= 1 }

    /// How many of the three rings are closed, and whether all are.
    var metCount: Int { (inRangeMet ? 1 : 0) + (activeMet ? 1 : 0) + (coverageMet ? 1 : 0) }
    var allMet: Bool { metCount == 3 }

    private func fraction(_ value: Double, of goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    /// Builds the rings for the calendar day containing `now`.
    ///
    /// - Coverage is measured over the **elapsed** day (local midnight → now), so
    ///   early in the morning a full sensor still reads ~100 % rather than being
    ///   unfairly penalised for the hours that haven't happened yet.
    static func make(
        readings: [GlucoseReading],
        activity: [ActivityEntry],
        thresholds: GlucoseThresholds,
        inRangeGoalFraction: Double,
        activeGoalMinutes: Int,
        coverageGoalFraction: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyRings {
        let start = calendar.startOfDay(for: now)
        let elapsed = max(now.timeIntervalSince(start), 60)

        let todaysReadings = readings.filter { $0.isActive && $0.timestamp >= start && $0.timestamp <= now }
        let stats = StatisticsEngine.glucose(todaysReadings, thresholds: thresholds)

        let todaysActivity = activity.filter { $0.startTimestamp >= start && $0.startTimestamp <= now }
        let minutes = todaysActivity.reduce(0) { $0 + $1.durationMinutes }

        let coverage = GlucoseCoverage.coverage(readingCount: todaysReadings.count, window: elapsed)

        return DailyRings(
            inRangeFraction: stats.timeInRange,
            inRangeGoalFraction: inRangeGoalFraction,
            activeMinutes: minutes,
            activeGoalMinutes: activeGoalMinutes,
            coverageFraction: coverage,
            coverageGoalFraction: coverageGoalFraction,
            hasGlucose: stats.hasGlucose
        )
    }
}
