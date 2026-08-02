import Foundation
import SwiftData

/// Fills an EMPTY journal with one convincing week of sample data, so someone
/// installing without a sensor sees the app alive instead of a wall of empty
/// states. Every inserted id is remembered, so "Remove demo data" deletes
/// exactly what was seeded and nothing the user logged themselves.
///
/// The trace is a shaped day, not noise: a dawn drift up, meal rises with
/// their boluses ~15 minutes ahead, an afternoon walk that eases glucose down,
/// and a calm night — repeated with day-to-day jitter so the statistics have
/// something honest to chew on. Deterministic (seeded generator): everyone's
/// demo looks equally good.
@ModelActor
actor DemoDataSeeder {
    static let seededIDsKey = "demo.seededRecordIDs"

    /// Whether demo data is currently present (checked from any thread).
    nonisolated static var hasDemoData: Bool {
        !(UserDefaults.standard.stringArray(forKey: seededIDsKey) ?? []).isEmpty
    }

    /// Seeds only when the store holds no glucose at all — demo data must never
    /// mix into a real journal.
    func seedIfEmpty() -> Bool {
        let existing = (try? modelContext.fetchCount(FetchDescriptor<GlucoseReading>())) ?? 0
        guard existing == 0 else { return false }

        var ids: [String] = []
        var generator = SplitMix64(seed: 20_26)
        let calendar = Calendar.current
        let now = Date()

        for dayOffset in stride(from: 6, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset,
                                               to: calendar.startOfDay(for: now)) else { continue }
            let dayEnd = dayOffset == 0 ? now : dayStart.addingTimeInterval(86_400)

            // Meals: three a day, with matching boluses shortly before.
            let meals: [(hour: Double, grams: Double, type: MealType, food: String)] = [
                (7.5 + jitter(&generator, 0.5), 40 + jitter(&generator, 8), .breakfast, "Oats & yogurt"),
                (13.0 + jitter(&generator, 0.6), 55 + jitter(&generator, 10), .lunch, "Chicken & rice"),
                (19.2 + jitter(&generator, 0.6), 50 + jitter(&generator, 10), .dinner, "Pasta"),
            ]
            for meal in meals {
                let at = dayStart.addingTimeInterval(meal.hour * 3600)
                guard at < dayEnd else { continue }
                let carb = CarbEntry(grams: meal.grams.rounded(), timestamp: at,
                                     mealType: meal.type, foodDescription: meal.food)
                modelContext.insert(carb)
                ids.append(carb.id.uuidString)
                let dose = InsulinDose(units: (meal.grams / 10).rounded(),
                                       timestamp: at.addingTimeInterval(-15 * 60),
                                       insulinType: .rapidActing)
                modelContext.insert(dose)
                ids.append(dose.id.uuidString)
            }

            // An afternoon walk most days.
            if dayOffset % 3 != 1 {
                let start = dayStart.addingTimeInterval((16.5 + jitter(&generator, 0.7)) * 3600)
                if start < dayEnd {
                    let walk = ActivityEntry(activityType: .walking, startTimestamp: start,
                                             durationSeconds: 35 * 60, intensity: .moderate)
                    modelContext.insert(walk)
                    ids.append(walk.id.uuidString)
                }
            }

            // The CGM trace: every 5 minutes, shaped by the day's events.
            var t = dayStart
            while t < dayEnd {
                let hour = t.timeIntervalSince(dayStart) / 3600
                var value = 105.0
                value += 14 * sin((hour - 4) / 24 * 2 * .pi)          // dawn drift
                for meal in meals {
                    let dt = hour - meal.hour
                    if dt > 0 { value += meal.grams * 1.15 * exp(-pow(dt - 1.0, 2) / 0.9) }
                }
                if dayOffset % 3 != 1 {
                    let dt = hour - 16.5
                    if dt > 0 { value -= 22 * exp(-pow(dt - 0.8, 2) / 1.2) }
                }
                value += jitter(&generator, 6)
                value = min(240, max(62, value))

                let reading = GlucoseReading(valueMgdL: value.rounded(), timestamp: t,
                                             source: .manual, measurementType: .cgm)
                modelContext.insert(reading)
                ids.append(reading.id.uuidString)
                t = t.addingTimeInterval(5 * 60)
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(ids, forKey: Self.seededIDsKey)
        return true
    }

    /// Deletes exactly the seeded records, by remembered id.
    func removeAll() -> Int {
        let idStrings = UserDefaults.standard.stringArray(forKey: Self.seededIDsKey) ?? []
        let ids = Set(idStrings.compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty else { return 0 }

        var removed = 0
        for reading in (try? modelContext.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        where ids.contains(reading.id) {
            modelContext.delete(reading); removed += 1
        }
        for dose in (try? modelContext.fetch(FetchDescriptor<InsulinDose>())) ?? []
        where ids.contains(dose.id) {
            modelContext.delete(dose); removed += 1
        }
        for entry in (try? modelContext.fetch(FetchDescriptor<CarbEntry>())) ?? []
        where ids.contains(entry.id) {
            modelContext.delete(entry); removed += 1
        }
        for entry in (try? modelContext.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        where ids.contains(entry.id) {
            modelContext.delete(entry); removed += 1
        }
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: Self.seededIDsKey)
        return removed
    }

    /// Uniform noise in ±range, from the deterministic generator.
    private func jitter(_ generator: inout SplitMix64, _ range: Double) -> Double {
        (Double(generator.next() % 10_000) / 10_000 - 0.5) * 2 * range
    }
}

/// A tiny deterministic PRNG, so the demo week renders identically everywhere.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
