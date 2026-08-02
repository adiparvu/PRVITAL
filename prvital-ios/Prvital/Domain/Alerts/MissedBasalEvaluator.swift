import Foundation

/// The smart basal nudge: fires only when the usual basal time has passed and
/// NO basal dose was logged today — unlike the fixed daily reminder, which
/// rings whether or not the shot already happened.
///
/// Pure and deterministic. State is just the last day it fired, so one evening
/// produces at most one nudge.
enum MissedBasalEvaluator {
    /// Grace after the usual time before nagging.
    static let graceMinutes = 45.0
    /// Past this long after the usual time the moment is gone — a 3 AM nudge
    /// about last evening's basal helps nobody.
    static let windowHours = 6.0

    struct Decision: Equatable, Sendable {
        var fire: Bool
        /// Start-of-day stamp of the last fired nudge, carried through.
        var lastFiredDay: Date?
    }

    /// - Parameters:
    ///   - usualMinutesFromMidnight: when the user normally takes their basal.
    ///   - basalDoseTimes: timestamps of BASAL doses logged recently (bolus
    ///     doses must be filtered out by the caller).
    static func decide(
        now: Date,
        usualMinutesFromMidnight: Int,
        basalDoseTimes: [Date],
        lastFiredDay: Date?,
        calendar: Calendar = .current
    ) -> Decision {
        let today = calendar.startOfDay(for: now)
        let usual = today.addingTimeInterval(TimeInterval(usualMinutesFromMidnight * 60))
        let windowStart = usual.addingTimeInterval(graceMinutes * 60)
        let windowEnd = usual.addingTimeInterval(windowHours * 3600)

        guard now >= windowStart, now <= windowEnd else {
            return Decision(fire: false, lastFiredDay: lastFiredDay)
        }
        if let lastFiredDay, calendar.isDate(lastFiredDay, inSameDayAs: now) {
            return Decision(fire: false, lastFiredDay: lastFiredDay)
        }
        // Any basal logged today (or within the 12 hours before the usual time,
        // for the person who takes it after midnight) stands the nudge down.
        let coveredSince = usual.addingTimeInterval(-12 * 3600)
        let covered = basalDoseTimes.contains { $0 >= coveredSince && $0 <= now }
        guard !covered else {
            return Decision(fire: false, lastFiredDay: lastFiredDay)
        }
        return Decision(fire: true, lastFiredDay: today)
    }
}
