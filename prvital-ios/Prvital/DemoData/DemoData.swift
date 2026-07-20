import Foundation
import SwiftData

/// Seeds a realistic, deterministic dataset so every screen is immediately
/// explorable on first launch (mirroring the web/native demo-mode convention).
/// Values are synthesised from a smooth daily curve — no randomness — so builds
/// and previews are reproducible.
enum DemoData {

    @MainActor
    static func seedIfEmpty(into context: ModelContext, days: Int = 4) {
        let existing = (try? context.fetchCount(FetchDescriptor<GlucoseReading>())) ?? 0
        guard existing == 0 else { return }
        seed(into: context, days: days)
    }

    /// Removes any sample data an earlier build seeded into the live store, once.
    /// The live app shows only the user's own readings and entries.
    @MainActor
    static func removeSeededDataOnce(from context: ModelContext) {
        let defaults = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        let key = "demo.purged.v1"
        guard !defaults.bool(forKey: key) else { return }
        purgeSeededData(from: context)
        defaults.set(true, forKey: key)
    }

    /// Deletes the records this file seeds, matched by their demo signatures, so
    /// a real install is left with only genuine sensor and user data.
    @MainActor
    static func purgeSeededData(from context: ModelContext) {
        let glucose = (try? context.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        for reading in glucose where reading.externalID?.hasPrefix("demo-") == true {
            context.delete(reading)
        }
        let insulin = (try? context.fetch(FetchDescriptor<InsulinDose>())) ?? []
        for dose in insulin where dose.insulinName == "Tresiba" || dose.insulinName == "NovoRapid" {
            context.delete(dose)
        }
        let demoFoods: Set<String> = ["Oats & berries", "Chicken & rice", "Pasta"]
        let carbs = (try? context.fetch(FetchDescriptor<CarbEntry>())) ?? []
        for entry in carbs where entry.foodDescription.map(demoFoods.contains) == true {
            context.delete(entry)
        }
        let observations = (try? context.fetch(FetchDescriptor<ObservationEntry>())) ?? []
        for observation in observations where observation.text == "Busy day, short night." {
            context.delete(observation)
        }
        let activity = (try? context.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        for session in activity where session.activityType == .walking
            && session.durationSeconds == 1800 && (session.distanceMeters ?? 0) == 2400 {
            context.delete(session)
        }
        try? context.save()
    }

    @MainActor
    static func seed(into context: ModelContext, days: Int = 4) {
        let calendar = Calendar.current
        let now = Date()

        // CGM stream every 15 minutes from the primary sensor.
        var t = now.addingTimeInterval(-Double(days) * 86_400)
        while t <= now {
            let mgdL = curve(at: t, calendar: calendar)
            let reading = GlucoseReading(
                valueMgdL: mgdL,
                timestamp: t,
                source: .dexcom,
                measurementType: .cgm,
                trend: trend(at: t, calendar: calendar),
                sensorTimestamp: t,
                confidence: 0.95,
                deviceID: "Dexcom G7",
                externalID: "demo-\(Int(t.timeIntervalSince1970))"
            )
            context.insert(reading)
            t = t.addingTimeInterval(15 * 60)
        }

        // A manual finger-stick that conflicts with the sensor (demonstrates the
        // deterministic resolver: the user's primary source wins, alternative kept).
        let conflictTime = now.addingTimeInterval(-2 * 3600)
        context.insert(GlucoseReading(
            valueMgdL: curve(at: conflictTime, calendar: calendar) + 14,
            timestamp: conflictTime.addingTimeInterval(40),
            source: .manual, measurementType: .fingerstick,
            externalID: "demo-fingerstick"
        ))

        // Insulin, carbs, activity and an observation across each day.
        for day in 0..<days {
            let base = calendar.startOfDay(for: now.addingTimeInterval(-Double(day) * 86_400))
            insulin(context, at: base, hour: 8, units: 6, type: .rapidActing, context_: .mealBolus)
            insulin(context, at: base, hour: 13, units: 8, type: .rapidActing, context_: .mealBolus)
            insulin(context, at: base, hour: 19, units: 7, type: .rapidActing, context_: .mealBolus)
            insulin(context, at: base, hour: 22, units: 18, type: .longActing, context_: .basal)

            carbs(context, at: base, hour: 8, grams: 40, meal: .breakfast, food: "Oats & berries")
            carbs(context, at: base, hour: 13, grams: 60, meal: .lunch, food: "Chicken & rice")
            carbs(context, at: base, hour: 19, grams: 55, meal: .dinner, food: "Pasta")

            let walk = ActivityEntry(activityType: .walking, startTimestamp: at(base, 18, 0),
                                     durationSeconds: 30 * 60, intensity: .moderate,
                                     caloriesBurned: 150, distanceMeters: 2400)
            context.insert(walk)

            if day == 1 {
                context.insert(ObservationEntry(tags: [.stress, .lackOfSleep],
                                                text: "Busy day, short night.",
                                                timestamp: at(base, 21, 30)))
            }
        }

        try? context.save()

        // Establish active/superseded flags for the seeded conflict.
        let all = (try? context.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        ConflictResolver().resolve(all)
        try? context.save()
    }

    // MARK: Curve

    /// A smooth glucose curve: overnight ~110, meal excursions at 8/13/19h.
    private static func curve(at date: Date, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
        var value = 112.0
        for mealHour in [8.0, 13.0, 19.0] {
            let delta = hour - mealHour
            if delta >= 0 && delta < 3 {
                value += 65 * exp(-pow(delta - 0.8, 2) / 0.5) // rise then fall
            }
        }
        // Gentle overnight dip.
        if hour < 6 { value -= 10 * cos(hour / 6 * .pi) }
        return max(62, min(255, value))
    }

    private static func trend(at date: Date, calendar: Calendar) -> GlucoseTrend {
        let a = curve(at: date, calendar: calendar)
        let b = curve(at: date.addingTimeInterval(-15 * 60), calendar: calendar)
        switch a - b {
        case 15...: return .risingFast
        case 4..<15: return .rising
        case -4...4: return .stable
        case -15 ..< -4: return .falling
        default: return .fallingFast
        }
    }

    // MARK: Helpers

    private static func at(_ base: Date, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    @MainActor
    private static func insulin(_ ctx: ModelContext, at base: Date, hour: Int, units: Double, type: InsulinType, context_: InsulinDoseContext) {
        ctx.insert(InsulinDose(units: units, timestamp: at(base, hour, 0), insulinType: type,
                               insulinName: type.isBasal ? "Tresiba" : "NovoRapid",
                               deliveryMethod: .pen, doseContext: context_))
    }

    @MainActor
    private static func carbs(_ ctx: ModelContext, at base: Date, hour: Int, grams: Double, meal: MealType, food: String) {
        ctx.insert(CarbEntry(grams: grams, timestamp: at(base, hour, 5), mealType: meal, foodDescription: food))
    }
}
