import Foundation

/// Chooses the single most relevant encyclopedia article to surface on the Panou,
/// from the last few hours of glucose — turning the app from one that just *shows*
/// numbers into one that *teaches* about what actually happened to you today. This
/// is the connective tissue of a "Health OS": your data on the Panou points you
/// straight to the lesson in Învață that fits your situation.
///
/// Pure and testable; the view maps `articleID` to an article and shows a short
/// reason line.
struct ContextualLesson: Equatable, Sendable {
    enum Situation: String, Equatable, Sendable {
        case recentLow
        case postMealHigh
        case dawnRise
        case recentHigh
        case steady
    }

    let situation: Situation

    /// The encyclopedia article id this situation should teach. These ids exist in
    /// `LearnLibrary.articles`.
    var articleID: String {
        switch situation {
        case .recentLow:    return "hypoglycaemia"
        case .postMealHigh: return "carb-counting"
        case .dawnRise:     return "dawn-phenomenon"
        case .recentHigh:   return "hyperglycaemia"
        case .steady:       return "time-in-range"
        }
    }

    /// Picks a lesson from recent glucose values (mg/dL) against the user's target
    /// band. Priority, most specific cause first:
    ///  1. a low — the most urgent thing to understand;
    ///  2. a high after a logged meal — points to carb counting (the likely cause);
    ///  3. a morning high with no meal, when a dawn pattern is present — the dawn
    ///     phenomenon;
    ///  4. any other high — the generic highs article;
    ///  5. otherwise steady — reinforce why time in range matters.
    /// Values exactly on a boundary count as in range. Returns nil when there's
    /// nothing recent to teach from.
    static func make(
        recentMgdL: [Double],
        targetLow: Double,
        targetHigh: Double,
        hadRecentMeal: Bool = false,
        dawnRiseLikely: Bool = false
    ) -> ContextualLesson? {
        guard !recentMgdL.isEmpty else { return nil }
        if recentMgdL.contains(where: { $0 < targetLow }) {
            return ContextualLesson(situation: .recentLow)
        }
        let hasHigh = recentMgdL.contains(where: { $0 > targetHigh })
        if hasHigh {
            if hadRecentMeal { return ContextualLesson(situation: .postMealHigh) }
            if dawnRiseLikely { return ContextualLesson(situation: .dawnRise) }
            return ContextualLesson(situation: .recentHigh)
        }
        return ContextualLesson(situation: .steady)
    }
}
