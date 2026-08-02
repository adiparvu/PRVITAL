import Foundation

/// "Last time you ate this": what the same-named meal did to glucose before,
/// surfaced at the moment of logging it again — the point where it can still
/// change a decision.
struct MealMemoryRecall: Equatable, Sendable {
    let when: Date
    let grams: Double
    /// The glucose just before that meal, and the highest point within the
    /// post-meal window (mg/dL).
    let baselineMgdL: Double
    let peakMgdL: Double
    /// Minutes from the meal to that peak.
    let minutesToPeak: Int
    /// The dose actually taken with it, if one was logged within ±30 min.
    let dosedUnits: Double?

    var riseMgdL: Double { peakMgdL - baselineMgdL }
}

/// Pure lookup over value tuples — no SwiftData, fully testable.
enum MealMemory {
    static let postWindowHours = 3.0
    static let dosePairingWindow: TimeInterval = 30 * 60
    /// A name must be at least this long to match — "a" matching everything
    /// would surface nonsense.
    static let minimumQueryLength = 3

    /// The most recent past meal whose name matches `query` (case- and
    /// diacritic-insensitive, containment either way) that has enough glucose
    /// coverage to tell a story.
    static func recall(
        query: String,
        meals: [(date: Date, grams: Double, food: String?)],
        readings: [(date: Date, mgdL: Double)],
        doses: [(date: Date, units: Double)],
        now: Date = Date()
    ) -> MealMemoryRecall? {
        let needle = normalize(query)
        guard needle.count >= minimumQueryLength else { return nil }

        let sortedReadings = readings.sorted { $0.date < $1.date }
        let candidates = meals
            .filter { meal in
                // Only meals old enough to have a finished response.
                guard now.timeIntervalSince(meal.date) >= postWindowHours * 3600 else { return false }
                let name = normalize(meal.food ?? "")
                guard !name.isEmpty else { return false }
                return name.contains(needle) || needle.contains(name)
            }
            .sorted { $0.date > $1.date }

        for meal in candidates {
            let windowEnd = meal.date.addingTimeInterval(postWindowHours * 3600)
            let before = sortedReadings.last {
                $0.date <= meal.date && meal.date.timeIntervalSince($0.date) <= 30 * 60
            }
            let after = sortedReadings.filter { $0.date > meal.date && $0.date <= windowEnd }
            guard let before, after.count >= 3,
                  let peak = after.max(by: { $0.mgdL < $1.mgdL }) else { continue }
            let dose = doses
                .filter { abs($0.date.timeIntervalSince(meal.date)) <= dosePairingWindow }
                .min { abs($0.date.timeIntervalSince(meal.date)) < abs($1.date.timeIntervalSince(meal.date)) }
            return MealMemoryRecall(
                when: meal.date,
                grams: meal.grams,
                baselineMgdL: before.mgdL,
                peakMgdL: peak.mgdL,
                minutesToPeak: Int(peak.date.timeIntervalSince(meal.date) / 60),
                dosedUnits: dose?.units)
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
