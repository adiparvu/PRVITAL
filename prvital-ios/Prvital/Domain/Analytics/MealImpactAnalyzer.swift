import Foundation

/// The measured glucose excursion following a single meal: the baseline just
/// before eating, the peak reached within the post-meal window, how far glucose
/// rose, and how long it took to peak.
struct MealImpact: Identifiable, Sendable {
    let mealID: UUID
    let mealTime: Date
    let mealType: MealType
    let grams: Double
    /// Glucose at the meal (mg/dL), taken from the reading nearest the meal time.
    let baselineMgdL: Double
    /// Highest glucose (mg/dL) reached within the post-meal window.
    let peakMgdL: Double
    /// Minutes from the meal to the peak reading.
    let minutesToPeak: Int
    /// Rise from baseline to peak (mg/dL). Can be ≤ 0 if glucose only fell.
    var deltaMgdL: Double { peakMgdL - baselineMgdL }

    var id: UUID { mealID }
}

/// An aggregate over several meals — the typical post-meal rise and time-to-peak.
struct MealImpactSummary: Equatable, Sendable {
    let count: Int
    let averageRiseMgdL: Double
    let averageMinutesToPeak: Double
}

/// Pairs meals with the CGM trace to quantify their post-meal impact. Pure and
/// deterministic: it only reads the two record collections and never mutates
/// state, so the whole thing is unit-testable without a store.
///
/// For each meal it takes the baseline from the reading nearest the meal time
/// (within a short look-back), then the peak from readings inside the post-meal
/// window. A meal is only scored when both a baseline and at least one post-meal
/// reading exist, so gaps in the trace produce no misleading zeros.
enum MealImpactAnalyzer {
    /// How long after a meal we look for the glucose peak (post-prandial window).
    static let defaultWindowMinutes: Double = 120
    /// How far before a meal a reading may sit to count as the baseline.
    static let baselineLookbackMinutes: Double = 20
    /// A reading may be slightly *after* the meal time and still be the baseline
    /// (clocks and logging lag differ); keep this small.
    static let baselineForwardToleranceMinutes: Double = 5

    static func analyze(
        meals: [CarbEntry],
        readings: [GlucoseReading],
        windowMinutes: Double = defaultWindowMinutes,
        baselineLookbackMinutes: Double = baselineLookbackMinutes
    ) -> [MealImpact] {
        let active = readings
            .filter { $0.isActive }
            .sorted { $0.timestamp < $1.timestamp }
        guard !active.isEmpty else { return [] }

        let window = windowMinutes * 60
        let lookback = baselineLookbackMinutes * 60
        let forward = baselineForwardToleranceMinutes * 60

        return meals
            .filter { $0.grams > 0 }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { meal -> MealImpact? in
                let mealTime = meal.timestamp

                // Baseline: the reading nearest the meal within
                // [mealTime - lookback, mealTime + forwardTolerance].
                let baselineCandidates = active.filter {
                    $0.timestamp >= mealTime.addingTimeInterval(-lookback) &&
                    $0.timestamp <= mealTime.addingTimeInterval(forward)
                }
                guard let baseline = baselineCandidates.min(by: {
                    abs($0.timestamp.timeIntervalSince(mealTime)) < abs($1.timestamp.timeIntervalSince(mealTime))
                }) else { return nil }

                // Peak: the highest reading strictly after the meal, within the window.
                let postMeal = active.filter {
                    $0.timestamp > mealTime &&
                    $0.timestamp <= mealTime.addingTimeInterval(window)
                }
                guard let peak = postMeal.max(by: { $0.valueMgdL < $1.valueMgdL }) else { return nil }

                let minutesToPeak = Int((peak.timestamp.timeIntervalSince(mealTime) / 60).rounded())
                return MealImpact(
                    mealID: meal.id,
                    mealTime: mealTime,
                    mealType: meal.mealType,
                    grams: meal.grams,
                    baselineMgdL: baseline.valueMgdL,
                    peakMgdL: peak.valueMgdL,
                    minutesToPeak: minutesToPeak
                )
            }
    }

    /// Averages the rise and time-to-peak across impacts. Nil when there are none.
    static func summary(_ impacts: [MealImpact]) -> MealImpactSummary? {
        guard !impacts.isEmpty else { return nil }
        let n = Double(impacts.count)
        let rise = impacts.reduce(0) { $0 + $1.deltaMgdL } / n
        let toPeak = impacts.reduce(0) { $0 + Double($1.minutesToPeak) } / n
        return MealImpactSummary(count: impacts.count, averageRiseMgdL: rise, averageMinutesToPeak: toPeak)
    }
}
