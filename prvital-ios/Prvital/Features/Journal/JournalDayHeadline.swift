import Foundation

/// A one-line, plain-language headline for a Journal day card — it turns the day's
/// numbers into a readable story ("A strong day in range", "A few highs to smooth
/// out") so a card reads like a diary entry, not just a block of stats. This is the
/// same "Health OS" narrative touch the Panou got, brought to the Journal.
///
/// Pure and testable; the view maps `kind` to a localized string and `tone` to a
/// colour.
struct JournalDayHeadline: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case positive, neutral, caution }

    enum Kind: String, Equatable, Sendable {
        case excellentRange
        case goodRange
        case someLows
        case someHighs
        case toughDay
        case loggedOnly
    }

    let kind: Kind
    let tone: Tone

    /// Builds a headline from a day's stats. Returns nil for an empty day (nothing
    /// logged at all). Time-in-range sets the overall verdict; when the day dropped
    /// out of range, a low is called out before a high (the more urgent of the two).
    /// `timeInRange` is a 0...1 fraction, matching `JournalDayStats`.
    static func make(stats: JournalDayStats, targetLow: Double, targetHigh: Double) -> JournalDayHeadline? {
        guard stats.hasGlucose else {
            return stats.entryCount > 0 ? JournalDayHeadline(kind: .loggedOnly, tone: .neutral) : nil
        }

        let tir = stats.timeInRange
        if tir >= 0.70 {
            return JournalDayHeadline(kind: .excellentRange, tone: .positive)
        }

        let hadLow = stats.lowestMgdL > 0 && stats.lowestMgdL < targetLow
        let hadHigh = stats.highestMgdL > targetHigh

        if tir >= 0.50 && !hadLow && !hadHigh {
            return JournalDayHeadline(kind: .goodRange, tone: .neutral)
        }
        if hadLow { return JournalDayHeadline(kind: .someLows, tone: .caution) }
        if hadHigh { return JournalDayHeadline(kind: .someHighs, tone: .caution) }
        return JournalDayHeadline(kind: .toughDay, tone: .caution)
    }
}
