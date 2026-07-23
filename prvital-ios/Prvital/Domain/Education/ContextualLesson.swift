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
        case recentHigh
        case steady
    }

    let situation: Situation

    /// The encyclopedia article id this situation should teach. These ids exist in
    /// `LearnLibrary.articles`.
    var articleID: String {
        switch situation {
        case .recentLow:  return "hypoglycaemia"
        case .recentHigh: return "hyperglycaemia"
        case .steady:     return "time-in-range"
        }
    }

    /// Picks a lesson from recent glucose values (mg/dL) against the user's target
    /// band. A low outranks a high — it's the more urgent thing to understand — and
    /// with neither, a steady stretch is a chance to reinforce why time in range
    /// matters. Values exactly on a boundary count as in range. Returns nil when
    /// there's nothing recent to teach from.
    static func make(recentMgdL: [Double], targetLow: Double, targetHigh: Double) -> ContextualLesson? {
        guard !recentMgdL.isEmpty else { return nil }
        if recentMgdL.contains(where: { $0 < targetLow }) {
            return ContextualLesson(situation: .recentLow)
        }
        if recentMgdL.contains(where: { $0 > targetHigh }) {
            return ContextualLesson(situation: .recentHigh)
        }
        return ContextualLesson(situation: .steady)
    }
}
