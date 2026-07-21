import Foundation

/// Turns the raw records into the compact `AchievementInputs` the evaluator
/// needs. Pure and deterministic given a calendar and reference date, so the
/// day-bucketing and thresholds are unit-testable in isolation.
enum AchievementInputsBuilder {
    /// Minimum readings for a day to count toward per-day milestones (mirrors
    /// `DailyBreakdown` so a stray reading can't earn a "perfect day").
    static let minReadingsPerDay = 6
    /// Fraction of the tight 70–140 range that marks a "steady" day.
    static let tightDayFraction = 0.5
    /// Window used to judge the estimated-A1c milestone.
    static let gmiWindowDays = 14

    static func make(
        readings: [GlucoseReading],
        meals: [CarbEntry],
        thresholds: GlucoseThresholds,
        goalFraction: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AchievementInputs {
        var inputs = AchievementInputs()
        let active = readings.filter(\.isActive)
        inputs.totalReadings = active.count
        inputs.loggedMeals = meals.count

        // Bucket by local day.
        var byDay: [Date: [GlucoseReading]] = [:]
        for r in active {
            byDay[calendar.startOfDay(for: r.timestamp), default: []].append(r)
        }
        inputs.daysWithData = byDay.count

        // Per-day stats for days with enough readings drive the "quality" badges.
        var perfect = 0, tight = 0
        var dayTIRs: [DayTIR] = []
        for (day, dayReadings) in byDay where dayReadings.count >= minReadingsPerDay {
            let stats = StatisticsEngine.glucose(dayReadings, thresholds: thresholds)
            dayTIRs.append(DayTIR(day: day, timeInRange: stats.timeInRange, readingCount: stats.readingCount))
            if stats.timeInRange >= 1.0 { perfect += 1 }
            if stats.timeInTightRange >= tightDayFraction { tight += 1 }
        }
        inputs.perfectDays = perfect
        inputs.tightDays = tight

        let streak = StreakCalculator.evaluate(
            days: dayTIRs.sorted { $0.day < $1.day },
            targetFraction: goalFraction, reference: now, calendar: calendar)
        inputs.currentStreakDays = streak.current
        inputs.bestStreakDays = streak.best

        // Estimated A1c over the recent window, when there's enough to trust it.
        let cutoff = calendar.date(byAdding: .day, value: -gmiWindowDays, to: now) ?? now
        let recent = active.filter { $0.timestamp >= cutoff }
        let windowStats = StatisticsEngine.glucose(recent, thresholds: thresholds)
        let coverage = GlucoseCoverage.coverage(
            readingCount: windowStats.readingCount,
            window: TimeInterval(gmiWindowDays) * 24 * 3600)
        if windowStats.hasGlucose, GlucoseCoverage.isReliable(coverage) {
            inputs.bestGmi = windowStats.glucoseManagementIndicator
        }
        return inputs
    }
}
