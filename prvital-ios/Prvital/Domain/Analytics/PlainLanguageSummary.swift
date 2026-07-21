import Foundation

/// The period a plain-language summary covers.
enum SummaryPeriod: Sendable {
    case today
    case week

    var title: String {
        switch self {
        case .today: return String(localized: "Today in plain words")
        case .week: return String(localized: "Your week in plain words")
        }
    }

    /// A lowercase noun for mid-sentence use ("…of the day / week").
    var noun: String {
        switch self {
        case .today: return String(localized: "day")
        case .week: return String(localized: "week")
        }
    }
}

/// A narrative summary: a headline plus a few plain sentences.
struct PlainLanguageSummary: Equatable, Sendable {
    let headline: String
    let sentences: [String]
}

/// Turns the numbers into a few sentences anyone can read — the "data in plain
/// language" idea, done supportively. Pure and deterministic; every clause is a
/// direct function of the statistics, so it's fully testable and never invents
/// anything the data doesn't say.
enum PlainLanguageSummarizer {
    /// Consensus cutoff for a "steady" coefficient of variation.
    static let steadyCVThreshold = 0.36

    static func summary(
        stats: PeriodStatistics,
        period: SummaryPeriod,
        goalFraction: Double,
        unit: GlucoseUnit
    ) -> PlainLanguageSummary {
        guard stats.hasGlucose else {
            return PlainLanguageSummary(
                headline: period.title,
                sentences: [String(localized: "There aren't enough readings yet to sum up your \(period.noun). Keep logging and this fills in.")])
        }

        var sentences: [String] = []
        let tir = Int((stats.timeInRange * 100).rounded())
        let goalPct = Int((goalFraction * 100).rounded())

        // Time in range, with a supportive comparison to the goal.
        if goalFraction > 0 && stats.timeInRange >= goalFraction {
            sentences.append(String(localized: "You were in range \(tir)% of the \(period.noun) — at or above your \(goalPct)% goal. Well done."))
        } else if goalFraction > 0 && stats.timeInRange >= goalFraction - 0.1 {
            sentences.append(String(localized: "You were in range \(tir)% of the \(period.noun), just shy of your \(goalPct)% goal — really close."))
        } else {
            sentences.append(String(localized: "You were in range \(tir)% of the \(period.noun). Every bit of steadiness counts."))
        }

        // Average and estimated A1c.
        let avg = GlucoseFormatting.labeled(mgdL: stats.average, unit: unit)
        let a1c = stats.glucoseManagementIndicator.formatted(.number.precision(.fractionLength(1)))
        sentences.append(String(localized: "Your average was \(avg), an estimated A1c of about \(a1c)%."))

        // Lows — mentioned gently but clearly, since they matter most for safety.
        let belowPct = Int((stats.timeBelowRange * 100).rounded())
        if stats.timeVeryLow > 0 {
            sentences.append(String(localized: "You had some very low readings — worth reviewing what led up to them."))
        } else if belowPct >= 4 {
            sentences.append(String(localized: "You spent \(belowPct)% below range. Easing off lows is usually the first win."))
        }

        // Highs.
        let abovePct = Int((stats.timeAboveRange * 100).rounded())
        if abovePct >= 30 {
            sentences.append(String(localized: "Highs took up \(abovePct)% of the \(period.noun) — a spot to look at meals or timing."))
        }

        // Variability.
        if stats.coefficientOfVariation > 0 {
            let cv = Int((stats.coefficientOfVariation * 100).rounded())
            if stats.coefficientOfVariation <= steadyCVThreshold {
                sentences.append(String(localized: "Your glucose was nicely steady (variability \(cv)%)."))
            } else {
                sentences.append(String(localized: "Your glucose swung a fair bit (variability \(cv)%). Smoother is easier on you."))
            }
        }

        return PlainLanguageSummary(headline: period.title, sentences: sentences)
    }
}
