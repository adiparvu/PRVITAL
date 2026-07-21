import Foundation

/// Ranks the user's favorite meals for the carb-entry sheet ("you usually have
/// this around now").
///
/// Pure and SwiftData-free: it operates on lightweight `Candidate` values, so
/// the ordering is unit-testable without a model container. The rule, in order:
///   1. favorites whose usual time is within ±90 minutes of "now" come first,
///      closest to now first (distance wraps around midnight);
///   2. then by `timesUsed`, most-used first;
///   3. then by `lastUsedAt`, most recent first (never-used last);
///   4. then by name, so the order is deterministic.
enum FavoriteMealSuggester {
    /// Minutes either side of "now" that count as "around this time".
    static let timeWindowMinutes = 90

    /// The ranking-relevant fields of a `FavoriteMeal`, decoupled from SwiftData.
    struct Candidate: Equatable, Sendable {
        var id: UUID
        var name: String
        var usualMinutesFromMidnight: Int?
        var timesUsed: Int
        var lastUsedAt: Date?

        init(
            id: UUID = UUID(),
            name: String = "",
            usualMinutesFromMidnight: Int? = nil,
            timesUsed: Int = 0,
            lastUsedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.usualMinutesFromMidnight = usualMinutesFromMidnight
            self.timesUsed = timesUsed
            self.lastUsedAt = lastUsedAt
        }
    }

    /// The candidates sorted per the rule above.
    static func ranked(_ candidates: [Candidate], nowMinutesFromMidnight: Int) -> [Candidate] {
        candidates.sorted { lhs, rhs in
            let lDistance = windowDistance(of: lhs, from: nowMinutesFromMidnight)
            let rDistance = windowDistance(of: rhs, from: nowMinutesFromMidnight)
            if lDistance != rDistance {
                switch (lDistance, rDistance) {
                case let (l?, r?): return l < r
                case (.some, nil): return true
                default: return false
                }
            }
            if lhs.timesUsed != rhs.timesUsed { return lhs.timesUsed > rhs.timesUsed }
            let lLast = lhs.lastUsedAt ?? .distantPast
            let rLast = rhs.lastUsedAt ?? .distantPast
            if lLast != rLast { return lLast > rLast }
            return lhs.name < rhs.name
        }
    }

    /// Distance in minutes between two times of day, wrapping around midnight
    /// (23:30 vs 00:30 is 60 minutes apart, not 1380).
    static func clockDistance(_ a: Int, _ b: Int) -> Int {
        let raw = abs(a - b) % 1440
        return min(raw, 1440 - raw)
    }

    /// A favorite's new `usualMinutesFromMidnight` after being logged again.
    ///
    /// A deliberately simple running blend: the midpoint of the stored value and
    /// the new log's minutes-from-midnight, taken along the shorter way around
    /// the clock so meals near midnight don't drift toward noon. First-ever use
    /// just adopts the new time.
    static func blendedUsualMinutes(current: Int?, newMinutes: Int) -> Int {
        let new = normalized(newMinutes)
        guard let current else { return new }
        let old = normalized(current)
        var delta = new - old
        if delta > 720 { delta -= 1440 }
        if delta < -720 { delta += 1440 }
        return normalized(old + delta / 2)
    }

    /// Minutes from local midnight for a concrete date (0...1439).
    static func minutesFromMidnight(of date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: Internals

    /// The wrap-around distance from "now", or nil when the candidate has no
    /// usual time yet or sits outside the ±`timeWindowMinutes` window.
    private static func windowDistance(of candidate: Candidate, from nowMinutes: Int) -> Int? {
        guard let usual = candidate.usualMinutesFromMidnight else { return nil }
        let distance = clockDistance(usual, nowMinutes)
        return distance <= timeWindowMinutes ? distance : nil
    }

    private static func normalized(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }
}
