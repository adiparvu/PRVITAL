import Foundation

/// Total and average carbohydrates for one meal type over a period.
struct MealTypeCarbs: Identifiable, Sendable {
    let mealType: MealType
    let totalGrams: Double
    let count: Int

    var id: String { mealType.rawValue }
    var averageGrams: Double { count > 0 ? totalGrams / Double(count) : 0 }
}

/// Groups carbohydrate entries by meal type. Pure and deterministic; entries
/// with no carbs are ignored, and the result is ordered by the canonical meal
/// sequence (breakfast → snacks → dinner), including only meal types that have
/// entries.
enum CarbDistribution {
    static func byMealType(_ entries: [CarbEntry]) -> [MealTypeCarbs] {
        let valid = entries.filter { $0.grams > 0 }
        guard !valid.isEmpty else { return [] }

        return MealType.allCases.compactMap { type in
            let matching = valid.filter { $0.mealType == type }
            guard !matching.isEmpty else { return nil }
            return MealTypeCarbs(
                mealType: type,
                totalGrams: matching.reduce(0) { $0 + $1.grams },
                count: matching.count
            )
        }
    }
}
