import Foundation

/// A motivational time-in-range streak, in the spirit of Apple's activity rings.
///
/// Pure and deterministic: given each day's time-in-range fraction and a target
/// fraction it reports the current run of consecutive goal-meeting days, the best
/// such run on record, and whether today already counts. There is no SwiftUI or
/// SwiftData here — it takes plain values and an injectable calendar so the
/// day-boundary logic is unit-testable in complete isolation.
enum StreakCalculator {

    /// The outcome of a streak evaluation.
    struct StreakResult: Equatable, Sendable {
        /// Consecutive goal-meeting days ending today — or ending yesterday when
        /// today has no data yet, since a day still "in progress" must not break
        /// an existing streak.
        var current: Int
        /// The longest run of consecutive goal-meeting days anywhere in the input.
        var best: Int
        /// Whether today's time-in-range already meets the target.
        var todayMet: Bool

        static let none = StreakResult(current: 0, best: 0, todayMet: false)
    }

    /// Computes the streak from per-day time-in-range.
    ///
    /// A day "meets" the goal when its time-in-range fraction is at least
    /// `targetFraction`. The current streak counts backwards from `reference`'s
    /// day: today is included when it meets the goal; a today with no data is
    /// treated as still in progress and counting resumes from yesterday; a today
    /// that has data but falls short ends the streak at zero. Any missing or short
    /// day earlier in the run breaks it, exactly as a missed ring day would.
    ///
    /// - Parameters:
    ///   - days: Per-day time-in-range, as produced by `DailyBreakdown.perDay`.
    ///   - targetFraction: The goal expressed as a 0…1 fraction (0.70 = 70% TIR).
    ///   - reference: "Now"; its local day is treated as today.
    ///   - calendar: Calendar used for day bucketing (injectable for tests).
    static func evaluate(
        days: [DayTIR],
        targetFraction: Double,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakResult {
        guard !days.isEmpty else { return .none }

        // Map each calendar day to whether it met the goal. DailyBreakdown yields
        // one entry per day; if a day somehow repeats, the later entry wins.
        var met: [Date: Bool] = [:]
        for day in days {
            met[calendar.startOfDay(for: day.day)] = day.timeInRange >= targetFraction
        }
        return compute(met: met, reference: reference, calendar: calendar)
    }

    /// A streak from a daily health metric (steps, active energy, exercise…): a
    /// day "meets" the goal when its value is at least `goal`. Uses the same
    /// today-in-progress rule as the Time-in-Range streak, so a partial today
    /// never breaks an existing run.
    static func evaluate(
        dailyValues: [(day: Date, value: Double)],
        goal: Double,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakResult {
        guard goal > 0, !dailyValues.isEmpty else { return .none }
        var met: [Date: Bool] = [:]
        for entry in dailyValues {
            met[calendar.startOfDay(for: entry.day)] = entry.value >= goal
        }
        return compute(met: met, reference: reference, calendar: calendar)
    }

    /// The shared streak core: given each day's met/not-met, count the current run
    /// back from today (a data-less today is treated as still in progress) and the
    /// best run anywhere in the input.
    private static func compute(met: [Date: Bool], reference: Date, calendar: Calendar) -> StreakResult {
        let today = calendar.startOfDay(for: reference)
        let todayMet = met[today] == true

        // Current streak: walk back a day at a time from the anchor. When today
        // has no data yet it is "in progress", so anchor at yesterday rather than
        // penalising the streak. When today has data but fell short the anchor is
        // today itself and the loop below stops immediately (current = 0).
        var cursor = today
        if met[today] == nil {
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        var current = 0
        while met[cursor] == true {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Best streak: the longest run of consecutive met days across all input.
        let metDaysSorted = met.filter { $0.value }.keys.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in metDaysSorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }

        return StreakResult(current: current, best: best, todayMet: todayMet)
    }
}
