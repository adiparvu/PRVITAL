import Foundation

/// One actionable, supportive suggestion derived from the user's own patterns.
/// Advice is general and non-prescriptive — it always points back to the care
/// team for anything that changes doses.
struct CoachingTip: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Lower sorts first; lows are the most urgent.
    let priority: Int
}

/// Turns detected glucose patterns into a short, prioritised list of gentle,
/// actionable tips (the "coaching" many apps do, done supportively). Pure and
/// deterministic, so it's fully testable.
enum PatternCoach {
    /// Coefficient of variation above which glucose is meaningfully "swingy".
    static let highCVThreshold = 0.36

    static func tips(
        insights: [GlucoseInsight],
        stats: PeriodStatistics,
        maxTips: Int = 3
    ) -> [CoachingTip] {
        var tips: [CoachingTip] = []

        for insight in insights {
            tips.append(tip(for: insight))
        }

        // A variability nudge when things are swingy but no single period stands out.
        if stats.hasGlucose, stats.coefficientOfVariation > highCVThreshold, tips.count < maxTips {
            tips.append(CoachingTip(
                id: "variability",
                title: String(localized: "Smooth out the swings"),
                detail: String(localized: "Your glucose bounces around a fair bit. Consistent meal timing and pre-bolusing a few minutes before eating tend to steady it."),
                symbol: "waveform.path.ecg",
                priority: 5))
        }

        // Nothing to flag — reassure, don't invent problems.
        if tips.isEmpty {
            tips.append(CoachingTip(
                id: "steady",
                title: String(localized: "Steady as you go"),
                detail: String(localized: "No strong time-of-day patterns right now — a good sign your days are consistent. Keep doing what works."),
                symbol: "checkmark.seal.fill",
                priority: 9))
        }

        return Array(tips.sorted { $0.priority < $1.priority }.prefix(maxTips))
    }

    private static func tip(for insight: GlucoseInsight) -> CoachingTip {
        let period = insight.period
        let isLow = insight.kind == .frequentLow
        let priority = isLow ? 0 : 2
        let symbol = isLow ? "arrow.down.circle.fill" : "arrow.up.circle.fill"

        let title = isLow
            ? String(localized: "Lows in the \(period.label.lowercased())")
            : String(localized: "Highs in the \(period.label.lowercased())")

        let detail: String
        switch (period, isLow) {
        case (.overnight, true):
            detail = String(localized: "You dip low overnight fairly often. A smaller evening dose or a bedtime snack can help — worth raising with your care team.")
        case (.morning, true):
            detail = String(localized: "Mornings tend to run low. Review your morning insulin-to-carb timing and keep fast carbs within reach.")
        case (.afternoon, true):
            detail = String(localized: "Afternoon lows show up often. Daytime activity or a lighter lunch dose may be a factor — a small tweak can smooth it.")
        case (.evening, true):
            detail = String(localized: "Evening lows appear often. Check your dinner dose and any late-day activity with your team.")
        case (.overnight, false):
            detail = String(localized: "You tend to run high overnight. Dinner timing and size, or your basal, may be worth reviewing with your team.")
        case (.morning, false):
            detail = String(localized: "Mornings run high — a dawn effect is common. A small pre-breakfast adjustment can help; ask your team before changing doses.")
        case (.afternoon, false):
            detail = String(localized: "Afternoons trend high. Bolusing a little earlier before lunch can blunt the spike.")
        case (.evening, false):
            detail = String(localized: "Evenings run high. Lighter dinner carbs or an earlier bolus may help.")
        }

        return CoachingTip(id: "\(period.rawValue)-\(insight.kind.rawValue)",
                           title: title, detail: detail, symbol: symbol, priority: priority)
    }
}
