import Foundation

/// One day inside the digest week, used for the best / toughest day callouts.
/// A small named struct rather than a tuple so the summary stays `Equatable`.
struct WeeklyDigestDay: Equatable, Sendable {
    let day: Date
    let timeInRange: Double
}

/// Everything the Monday "week in review" screen shows, precomputed as plain
/// values so the view only formats and renders.
struct WeeklyDigestSummary: Equatable, Sendable {
    /// Monday 00:00 (local) of the digested week.
    let weekStart: Date
    /// Time-in-range fraction (0…1) for the week.
    let timeInRange: Double
    /// Change vs the week before, in 0…1 points (current − previous). `nil` when
    /// the previous week has no glucose data to compare against.
    let timeInRangeDelta: Double?
    /// Mean glucose for the week, mg/dL.
    let averageMgdL: Double
    /// Glucose Management Indicator (estimated A1c, %).
    let gmiPercent: Double
    let readingCount: Int
    /// Highest-TIR day of the week; `nil` unless at least two days qualify (a
    /// single qualifying day would be its own "best" and "toughest").
    let bestDay: WeeklyDigestDay?
    /// Lowest-TIR day of the week, under the same two-day rule.
    let toughestDay: WeeklyDigestDay?
    /// Distinct low excursion events (contiguous runs below range), not raw
    /// reading counts — a two-hour low counts once.
    let lowsCount: Int
    /// Distinct high excursion events, same event convention as `lowsCount`.
    let highsCount: Int
    /// Consecutive days meeting the TIR streak target, ending at the week's
    /// Sunday (or its last day with data).
    let streakDays: Int
    /// The single most notable fact about the week, ready to display.
    let headline: String
}

/// Pure composer for the Monday "week in review" digest. Foundation only — no
/// SwiftUI, no SwiftData queries — so the whole summary is unit-testable.
///
/// **Week convention:** the digest always covers the most recent *complete*
/// Monday–Sunday week strictly before the reference date's week. The week
/// containing the reference is never included — even when the reference falls on
/// a Sunday, that week is still "in progress". Monday is fixed as the week start
/// regardless of the calendar's `firstWeekday`, so the digest reads the same in
/// every locale. The comparison week is the Monday–Sunday block immediately
/// before the digest week.
enum WeeklyDigest {

    /// A week needs data on at least this many distinct days to produce a digest.
    static let minDaysWithData = 3
    /// A TIR change must reach this many rounded points before the headline
    /// calls the week better or tougher; smaller moves read as "steady".
    static let headlineDeltaPoints = 3
    /// Default TIR goal for the streak, matching `GlucoseGoals`' 70% default.
    static let defaultStreakTargetFraction = 0.70

    /// The most recent complete Monday–Sunday week before `reference`, as a
    /// half-open interval `[Monday 00:00, next Monday 00:00)`.
    static func lastFullWeek(before reference: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: reference)
        // Gregorian weekday: 1 = Sunday … 7 = Saturday, so Monday is 2. The
        // offset is computed explicitly (not via `firstWeekday`) to pin the
        // Monday convention in every locale.
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let currentWeekMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -7, to: currentWeekMonday) ?? currentWeekMonday
        return DateInterval(start: start, end: currentWeekMonday)
    }

    /// Builds the digest for the last full week before `referenceDate`, or `nil`
    /// when that week has active readings on fewer than `minDaysWithData`
    /// distinct days. `insulin`, `carbs` and `activity` are accepted for a
    /// complete call site (mirroring `InsightFeed.build`) but no summary field
    /// consumes them yet.
    static func compose(
        readings: [GlucoseReading],
        insulin: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        activity: [ActivityEntry] = [],
        thresholds: GlucoseThresholds,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        streakTargetFraction: Double = defaultStreakTargetFraction
    ) -> WeeklyDigestSummary? {
        _ = (insulin, carbs, activity)

        let week = lastFullWeek(before: referenceDate, calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start

        let weekReadings = readings.filter {
            $0.isActive && $0.timestamp >= week.start && $0.timestamp < week.end
        }

        let daysWithData = Set(weekReadings.map { calendar.startOfDay(for: $0.timestamp) })
        guard daysWithData.count >= minDaysWithData else { return nil }

        let stats = StatisticsEngine.glucose(weekReadings, thresholds: thresholds)
        guard stats.hasGlucose else { return nil }

        let previousReadings = readings.filter {
            $0.isActive && $0.timestamp >= previousStart && $0.timestamp < week.start
        }
        let previousStats = StatisticsEngine.glucose(previousReadings, thresholds: thresholds)
        let delta: Double? = previousStats.hasGlucose
            ? stats.timeInRange - previousStats.timeInRange
            : nil

        // Per-day TIR drives the best/toughest callouts and the streak.
        // `DailyBreakdown` already drops days with too few readings, so a stray
        // single reading can't win "best day".
        let days = DailyBreakdown.perDay(weekReadings, thresholds: thresholds, calendar: calendar)
        let best = days.count >= 2 ? DailyBreakdown.best(days) : nil
        let worst = days.count >= 2 ? DailyBreakdown.worst(days) : nil

        // Anchor the streak at the week's Sunday; `StreakCalculator` steps back
        // to the last day with data when Sunday itself has none.
        let sunday = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        let streak = StreakCalculator.evaluate(
            days: days,
            targetFraction: streakTargetFraction,
            reference: sunday,
            calendar: calendar
        )

        return WeeklyDigestSummary(
            weekStart: week.start,
            timeInRange: stats.timeInRange,
            timeInRangeDelta: delta,
            averageMgdL: stats.average,
            gmiPercent: stats.glucoseManagementIndicator,
            readingCount: stats.readingCount,
            bestDay: best.map { WeeklyDigestDay(day: $0.day, timeInRange: $0.timeInRange) },
            toughestDay: worst.map { WeeklyDigestDay(day: $0.day, timeInRange: $0.timeInRange) },
            lowsCount: stats.hypoEvents,
            highsCount: stats.hyperEvents,
            streakDays: streak.current,
            headline: headline(timeInRange: stats.timeInRange, delta: delta)
        )
    }

    /// Picks the week's most notable fact. Rules, in order — positive-leaning
    /// but honest:
    /// 1. TIR up by ≥ `headlineDeltaPoints` rounded points → celebrate the rise.
    /// 2. TIR down by ≥ `headlineDeltaPoints` rounded points → acknowledge a
    ///    tougher week, stating the drop plainly.
    /// 3. Otherwise (small move, or no previous week to compare) → a steady
    ///    framing around the week's own TIR.
    static func headline(timeInRange: Double, delta: Double?) -> String {
        if let delta {
            let points = Int((delta * 100).rounded())
            if points >= headlineDeltaPoints {
                return "Time in range up \(points) points"
            }
            if points <= -headlineDeltaPoints {
                return "A tougher week — TIR down \(-points) points"
            }
        }
        let pct = Int((timeInRange * 100).rounded())
        return "Steady week: \(pct)% in range"
    }
}
