import Foundation

/// Pure carbohydrate pharmacodynamics: **carbs on board** (COB) — the grams of a
/// meal still being absorbed. The symmetric partner to `InsulinMath`'s IOB.
///
/// It uses a simple linear-absorption model over a fixed absorption time, which
/// is the common, transparent default (Loop/oref use a dynamic model that needs
/// live glucose response; a linear estimate is honest and predictable here).
/// Deterministic and unit-tested; it drives display only, never dosing.
enum CarbMath {
    /// Default absorption time (minutes) for a typical mixed meal.
    static let defaultAbsorptionMinutes: Double = 180

    /// Grams of carbohydrate still on board from `entries` as of `date`, under
    /// linear absorption over `absorptionMinutes`.
    static func carbsOnBoard(
        entries: [CarbEntry],
        at date: Date,
        absorptionMinutes: Double = defaultAbsorptionMinutes
    ) -> Double {
        guard absorptionMinutes > 0 else { return 0 }
        return entries.reduce(0) { total, entry in
            let elapsed = date.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0, elapsed < absorptionMinutes else { return total }
            let remainingFraction = 1 - elapsed / absorptionMinutes
            return total + max(0, entry.grams) * remainingFraction
        }
    }
}
