import Foundation

/// A meal the user keeps logging the same way — same food, same grams, and
/// (when they bolus for it) the dose they usually take with it. One tap in the
/// quick-entry hub re-logs the whole thing.
struct MealCombo: Equatable, Sendable, Identifiable {
    let foodDescription: String?
    let grams: Double
    /// The dose usually paired with it, nil when the meal is logged unbolused.
    let units: Double?
    let occurrences: Int
    let lastUsed: Date

    var id: String { "\(foodDescription ?? "")|\(Int(grams))|\(units.map { "\($0)" } ?? "-")" }
}

/// Finds the user's repeat meals in a recent window. Pure — takes value tuples,
/// so it's trivially testable and never touches SwiftData.
enum FrequentCombos {
    /// A dose within this many seconds of the meal counts as "taken with it".
    static let pairingWindow: TimeInterval = 20 * 60
    /// A combo needs at least this many occurrences to count as a habit.
    static let minimumOccurrences = 2

    static func detect(
        meals: [(date: Date, grams: Double, food: String?)],
        doses: [(date: Date, units: Double)],
        limit: Int = 3
    ) -> [MealCombo] {
        struct Key: Hashable {
            let food: String
            let gramsBucket: Int
        }
        var groups: [Key: [(date: Date, grams: Double, food: String?, units: Double?)]] = [:]

        let sortedDoses = doses.sorted { $0.date < $1.date }
        for meal in meals {
            // The dose logged closest to the meal, inside the pairing window.
            let paired = sortedDoses
                .filter { abs($0.date.timeIntervalSince(meal.date)) <= pairingWindow }
                .min { abs($0.date.timeIntervalSince(meal.date)) < abs($1.date.timeIntervalSince(meal.date)) }
            let normalized = (meal.food ?? "")
                .lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .trimmingCharacters(in: .whitespaces)
            // Unnamed meals only combine when the amount matches closely.
            let key = Key(food: normalized, gramsBucket: Int((meal.grams / 5).rounded()))
            groups[key, default: []].append((meal.date, meal.grams, meal.food, paired?.units))
        }

        return groups.values
            .compactMap { entries -> MealCombo? in
                guard entries.count >= minimumOccurrences,
                      let newest = entries.max(by: { $0.date < $1.date }) else { return nil }
                let doses = entries.compactMap(\.units)
                // The usual dose: the median of what was actually taken, or nil
                // when the meal is mostly logged without one.
                let usualDose: Double? = doses.count * 2 >= entries.count
                    ? doses.sorted()[doses.count / 2] : nil
                return MealCombo(
                    foodDescription: newest.food,
                    grams: newest.grams,
                    units: usualDose,
                    occurrences: entries.count,
                    lastUsed: newest.date)
            }
            .sorted {
                $0.occurrences != $1.occurrences
                    ? $0.occurrences > $1.occurrences
                    : $0.lastUsed > $1.lastUsed
            }
            .prefix(limit)
            .map { $0 }
    }
}
