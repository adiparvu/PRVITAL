import Foundation

/// Pure, deterministic carbohydrate maths for logging a food portion.
///
/// Nutrition is expressed per 100 g (the Open Food Facts convention); these
/// helpers scale it to the eaten portion and, optionally, subtract fibre to give
/// "net carbs". Everything here is display-only and safe with junk input.
enum CarbCalculator {

    /// Carbohydrate grams in `portionGrams` of a food with `carbsPer100g`.
    static func carbs(per100g carbsPer100g: Double, portionGrams: Double) -> Double {
        guard carbsPer100g > 0, portionGrams > 0 else { return 0 }
        return carbsPer100g * portionGrams / 100
    }

    /// Net carbs = total − fibre, never below zero.
    static func netCarbs(total: Double, fiber: Double) -> Double {
        max(0, total - max(0, fiber))
    }

    /// Carbohydrate grams for a portion, optionally subtracting the portion's
    /// fibre. `fiberPer100g` is only applied when `useNetCarbs` is true.
    static func carbs(
        portionGrams: Double,
        carbsPer100g: Double,
        fiberPer100g: Double? = nil,
        useNetCarbs: Bool = false
    ) -> Double {
        let total = carbs(per100g: carbsPer100g, portionGrams: portionGrams)
        guard useNetCarbs, let fiberPer100g, fiberPer100g > 0 else { return total }
        let fiber = carbs(per100g: fiberPer100g, portionGrams: portionGrams)
        return netCarbs(total: total, fiber: fiber)
    }

    /// The portion in grams that provides `targetCarbs` grams of carbohydrate.
    static func portionGrams(forTargetCarbs targetCarbs: Double, carbsPer100g: Double) -> Double {
        guard carbsPer100g > 0, targetCarbs > 0 else { return 0 }
        return targetCarbs / carbsPer100g * 100
    }
}
