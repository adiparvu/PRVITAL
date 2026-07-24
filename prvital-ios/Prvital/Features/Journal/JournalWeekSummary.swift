import Foundation

/// A one-glance "your week" summary for the top of the Journal: average time in
/// range over the last seven logged days, and whether that's up, down, or steady
/// versus the seven days before. It gives the day-card feed a sense of direction
/// without opening the detailed weekly digest. Pure and testable.
struct JournalWeekSummary: Equatable, Sendable {
    enum Trend: Equatable, Sendable { case up, steady, down }

    /// Mean time-in-range this week, as a 0...1 fraction.
    let timeInRange: Double
    /// How many days with glucose fed this week's average.
    let dayCount: Int
    /// Change vs the prior seven logged days, in TIR fraction points (this − prior).
    let delta: Double
    /// Whether there was a prior week to compare against.
    let hasComparison: Bool
    let trend: Trend

    /// A single day's contribution: its start-of-day date and its TIR fraction.
    /// Only days that actually have glucose should be passed in.
    struct Day: Equatable, Sendable {
        let day: Date
        let timeInRange: Double

        init(day: Date, timeInRange: Double) {
            self.day = day
            self.timeInRange = timeInRange
        }
    }

    /// Builds from per-day TIR values. `now` anchors the two seven-day windows.
    /// Returns nil when the current week has no glucose days. `steadyBand` is the
    /// change (in fraction points) below which the week counts as flat.
    static func make(
        days: [Day],
        now: Date,
        calendar: Calendar = .current,
        steadyBand: Double = 0.03
    ) -> JournalWeekSummary? {
        let startToday = calendar.startOfDay(for: now)
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: startToday),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: startToday) else {
            return nil
        }

        let thisWeek = days.filter { $0.day >= weekAgo && $0.day <= now }
        guard !thisWeek.isEmpty else { return nil }
        let priorWeek = days.filter { $0.day >= twoWeeksAgo && $0.day < weekAgo }

        let thisAvg = thisWeek.map(\.timeInRange).reduce(0, +) / Double(thisWeek.count)
        let priorAvg = priorWeek.isEmpty
            ? nil
            : priorWeek.map(\.timeInRange).reduce(0, +) / Double(priorWeek.count)
        let delta = priorAvg.map { thisAvg - $0 } ?? 0

        let trend: Trend
        if priorAvg == nil {
            trend = .steady
        } else if delta > steadyBand {
            trend = .up
        } else if delta < -steadyBand {
            trend = .down
        } else {
            trend = .steady
        }

        return JournalWeekSummary(
            timeInRange: thisAvg,
            dayCount: thisWeek.count,
            delta: delta,
            hasComparison: priorAvg != nil,
            trend: trend
        )
    }
}
