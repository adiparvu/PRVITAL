import Foundation

/// A tasteful milestone the user can earn. Purely descriptive — the rule that
/// unlocks it lives in `AchievementEvaluator`, keyed by `id`, so this stays a
/// plain, `Sendable` value with no logic or closures.
struct Achievement: Identifiable, Equatable, Sendable {
    let id: AchievementID
    let title: String
    let detail: String
    let symbol: String
    let tier: AchievementTier
    /// The count the user must reach to earn it (e.g. 7 streak days, 25 meals).
    let target: Int
}

enum AchievementTier: String, Sendable {
    case bronze, silver, gold
}

/// Stable identifiers for each achievement. Raw values are persisted, so never
/// rename or reuse one.
enum AchievementID: String, CaseIterable, Sendable {
    // Getting started
    case firstReading
    case firstMeal
    case weekOfData
    // Consistency
    case meals25
    case meals100
    case monthOfData
    // Control
    case streak7
    case streak14
    case streak30
    case perfectDay
    case tightWeek
    case steadyGmi
}

/// The full catalogue, grouped for display. Titles/details are localized at the
/// point of definition so the whole set travels as ready-to-show strings.
enum AchievementCatalog {
    static let all: [Achievement] = [
        // Getting started
        Achievement(id: .firstReading, title: String(localized: "First reading"),
                    detail: String(localized: "Log or sync your very first glucose reading."),
                    symbol: "drop.fill", tier: .bronze, target: 1),
        Achievement(id: .firstMeal, title: String(localized: "First meal"),
                    detail: String(localized: "Log your first meal to see how food moves your glucose."),
                    symbol: "fork.knife", tier: .bronze, target: 1),
        Achievement(id: .weekOfData, title: String(localized: "Week of data"),
                    detail: String(localized: "Record glucose on 7 different days."),
                    symbol: "calendar", tier: .bronze, target: 7),
        // Consistency
        Achievement(id: .meals25, title: String(localized: "Meal logger"),
                    detail: String(localized: "Log 25 meals."),
                    symbol: "list.bullet.clipboard", tier: .silver, target: 25),
        Achievement(id: .meals100, title: String(localized: "Century of meals"),
                    detail: String(localized: "Log 100 meals."),
                    symbol: "square.stack.3d.up.fill", tier: .gold, target: 100),
        Achievement(id: .monthOfData, title: String(localized: "Month of data"),
                    detail: String(localized: "Record glucose on 30 different days."),
                    symbol: "calendar.badge.clock", tier: .silver, target: 30),
        // Control
        Achievement(id: .streak7, title: String(localized: "One week in range"),
                    detail: String(localized: "Meet your time-in-range goal 7 days in a row."),
                    symbol: "flame.fill", tier: .silver, target: 7),
        Achievement(id: .streak14, title: String(localized: "Two weeks in range"),
                    detail: String(localized: "Meet your time-in-range goal 14 days in a row."),
                    symbol: "flame.fill", tier: .gold, target: 14),
        Achievement(id: .streak30, title: String(localized: "A month in range"),
                    detail: String(localized: "Meet your time-in-range goal 30 days in a row."),
                    symbol: "trophy.fill", tier: .gold, target: 30),
        Achievement(id: .perfectDay, title: String(localized: "Perfect day"),
                    detail: String(localized: "Spend a whole day 100% in range."),
                    symbol: "star.circle.fill", tier: .gold, target: 1),
        Achievement(id: .tightWeek, title: String(localized: "Steady week"),
                    detail: String(localized: "Have 7 days mostly in the tight 70–140 range."),
                    symbol: "target", tier: .silver, target: 7),
        Achievement(id: .steadyGmi, title: String(localized: "In target A1c"),
                    detail: String(localized: "Reach an estimated A1c of 7.0% or lower."),
                    symbol: "heart.text.square.fill", tier: .gold, target: 1),
    ]

    static func achievement(_ id: AchievementID) -> Achievement {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The compact, already-summarised facts the evaluator needs. Building this from
/// the store lives in the view; the evaluator itself stays pure and testable.
struct AchievementInputs: Equatable, Sendable {
    var totalReadings = 0
    var loggedMeals = 0
    var daysWithData = 0
    var currentStreakDays = 0
    var bestStreakDays = 0
    /// Days that were 100% in range (with enough readings to count).
    var perfectDays = 0
    /// Days that were mostly (≥ 50%) in the tight 70–140 range.
    var tightDays = 0
    /// Best (lowest) estimated A1c reached; nil when there isn't enough data.
    var bestGmi: Double?
}

/// Pure rules that turn `AchievementInputs` into progress and unlock state.
enum AchievementEvaluator {
    /// The `(current, target)` progress toward an achievement, both clamped ≥ 0.
    static func progress(_ id: AchievementID, _ inputs: AchievementInputs) -> (current: Int, target: Int) {
        let target = AchievementCatalog.achievement(id).target
        let current: Int
        switch id {
        case .firstReading: current = min(inputs.totalReadings, target)
        case .firstMeal: current = min(inputs.loggedMeals, target)
        case .weekOfData, .monthOfData: current = min(inputs.daysWithData, target)
        case .meals25, .meals100: current = min(inputs.loggedMeals, target)
        case .streak7, .streak14, .streak30: current = min(inputs.bestStreakDays, target)
        case .perfectDay: current = min(inputs.perfectDays, target)
        case .tightWeek: current = min(inputs.tightDays, target)
        case .steadyGmi: current = (inputs.bestGmi.map { $0 <= 7.0 } ?? false) ? target : 0
        }
        return (max(0, current), target)
    }

    static func isUnlocked(_ id: AchievementID, _ inputs: AchievementInputs) -> Bool {
        let p = progress(id, inputs)
        return p.current >= p.target
    }

    /// Every currently-earned achievement.
    static func unlocked(_ inputs: AchievementInputs) -> Set<AchievementID> {
        Set(AchievementID.allCases.filter { isUnlocked($0, inputs) })
    }
}
