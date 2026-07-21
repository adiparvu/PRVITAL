import Foundation

/// One point on the post-meal glucose curve.
struct MealResponsePoint: Identifiable, Sendable {
    let date: Date
    let mgdL: Double
    var id: Date { date }
}

/// A time marker on the response chart — the meal itself (`hoursAfter == 0`) and
/// each whole hour after it, with the reading nearest that instant (if any).
struct MealResponseMarker: Identifiable, Sendable {
    let hoursAfter: Int
    let date: Date
    let mgdL: Double?
    var id: Int { hoursAfter }

    var title: String {
        hoursAfter == 0
            ? String(localized: "Meal time")
            : String(localized: "+\(hoursAfter)h")
    }
}

/// How well a meal was handled, from the excursion and post-meal time in range.
enum MealResponseRating: String, Sendable {
    case steady      // barely moved / stayed in range
    case gentle      // modest rise, mostly in range
    case notable     // a real spike but recovered
    case high        // large spike or long time out of range

    var title: String {
        switch self {
        case .steady: String(localized: "Steady")
        case .gentle: String(localized: "Gentle rise")
        case .notable: String(localized: "Notable spike")
        case .high: String(localized: "High spike")
        }
    }
    var symbol: String {
        switch self {
        case .steady: "checkmark.seal.fill"
        case .gentle: "arrow.up.right"
        case .notable: "arrow.up.forward"
        case .high: "exclamationmark.triangle.fill"
        }
    }
}

/// The full postprandial response to a single meal: the curve over the window,
/// hour markers, and the metrics a person actually cares about — how high it
/// went, when, how long it stayed up, how much of the window was in range, and
/// what bolus (if any) accompanied the meal.
struct MealResponse: Sendable {
    let mealID: UUID
    let mealTime: Date
    let mealType: MealType
    let grams: Double
    let windowHours: Int

    let baselineMgdL: Double?
    let peakMgdL: Double?
    let minutesToPeak: Int?
    /// Minutes from the meal until glucose came back within 15 mg/dL of baseline
    /// (after peaking). Nil if it never did inside the window.
    let returnMinutes: Int?
    /// Area of the excursion above baseline, in mg/dL·hour — a single number for
    /// "how big" the response was that time-to-peak alone can't capture.
    let excursionAUC: Double
    /// Share of the window's readings that sat in the target range (0…1).
    let inRangePercent: Double?
    /// Bolus units logged within ±30 min of the meal, and when (nil if none).
    let bolusUnits: Double?
    let bolusAt: Date?

    let points: [MealResponsePoint]
    let markers: [MealResponseMarker]

    var deltaMgdL: Double? {
        guard let peakMgdL, let baselineMgdL else { return nil }
        return peakMgdL - baselineMgdL
    }

    /// True when there's enough of a trace to say anything useful.
    var hasData: Bool { points.count >= 2 }

    /// A qualitative verdict from the rise and how much of the window stayed in
    /// range. Deliberately forgiving — this is encouragement, not judgement.
    var rating: MealResponseRating {
        let rise = deltaMgdL ?? 0
        let tir = inRangePercent ?? 1
        switch (rise, tir) {
        case let (r, t) where r <= 30 && t >= 0.8: return .steady
        case let (r, t) where r <= 55 && t >= 0.6: return .gentle
        case let (r, _) where r <= 90: return .notable
        default: return .high
        }
    }
}

/// Builds a `MealResponse` for one meal from the CGM trace and insulin doses.
/// Pure and deterministic — unit-testable without a store.
enum MealResponseAnalyzer {
    /// A reading may sit this long before the meal and still be the baseline.
    static let baselineLookback: TimeInterval = 20 * 60
    /// …or slightly after (logging lag), kept small.
    static let baselineForward: TimeInterval = 5 * 60
    /// A reading counts toward an hour marker if within this of the target instant.
    static let markerTolerance: TimeInterval = 20 * 60
    /// Bolus doses within this of the meal are treated as "for" the meal.
    static let bolusWindow: TimeInterval = 30 * 60

    static func analyze(
        meal: CarbEntry,
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        thresholds: GlucoseThresholds,
        windowHours: Int
    ) -> MealResponse {
        let hours = min(4, max(1, windowHours))
        let mealTime = meal.timestamp
        let window = TimeInterval(hours) * 3600
        let windowEnd = mealTime.addingTimeInterval(window)

        let active = readings
            .filter(\.isActive)
            .sorted { $0.timestamp < $1.timestamp }

        // Baseline: reading nearest the meal within the look-back window.
        let baseline = active
            .filter { $0.timestamp >= mealTime.addingTimeInterval(-baselineLookback)
                   && $0.timestamp <= mealTime.addingTimeInterval(baselineForward) }
            .min { abs($0.timestamp.timeIntervalSince(mealTime)) < abs($1.timestamp.timeIntervalSince(mealTime)) }
        let baselineMgdL = baseline?.valueMgdL

        // The curve: readings from the meal (or its baseline) through the window.
        let curveStart = baseline?.timestamp ?? mealTime
        let inWindow = active.filter { $0.timestamp >= curveStart && $0.timestamp <= windowEnd }
        let points = inWindow.map { MealResponsePoint(date: $0.timestamp, mgdL: $0.valueMgdL) }

        // Peak strictly after the meal.
        let postMeal = inWindow.filter { $0.timestamp > mealTime }
        let peak = postMeal.max { $0.valueMgdL < $1.valueMgdL }
        let peakMgdL = peak?.valueMgdL
        let minutesToPeak = peak.map { Int(($0.timestamp.timeIntervalSince(mealTime) / 60).rounded()) }

        // Return-to-baseline after the peak.
        var returnMinutes: Int?
        if let baselineMgdL, let peak {
            if let back = postMeal.first(where: {
                $0.timestamp > peak.timestamp && $0.valueMgdL <= baselineMgdL + 15
            }) {
                returnMinutes = Int((back.timestamp.timeIntervalSince(mealTime) / 60).rounded())
            }
        }

        // Excursion area above baseline (trapezoidal), in mg/dL·hour.
        var auc = 0.0
        if let baselineMgdL, postMeal.count >= 2 {
            let series = ([baseline].compactMap { $0 } + postMeal)
            for (a, b) in zip(series, series.dropFirst()) {
                let dtHours = b.timestamp.timeIntervalSince(a.timestamp) / 3600
                let ea = max(0, a.valueMgdL - baselineMgdL)
                let eb = max(0, b.valueMgdL - baselineMgdL)
                auc += (ea + eb) / 2 * dtHours
            }
        }

        // Post-meal time in range.
        let inRangePercent: Double? = postMeal.isEmpty ? nil
            : Double(postMeal.filter { thresholds.inRange($0.valueMgdL) }.count) / Double(postMeal.count)

        // Hour markers.
        var markers: [MealResponseMarker] = []
        for h in 0...hours {
            let target = mealTime.addingTimeInterval(TimeInterval(h) * 3600)
            let near = active
                .filter { abs($0.timestamp.timeIntervalSince(target)) <= markerTolerance }
                .min { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) }
            markers.append(MealResponseMarker(hoursAfter: h, date: target, mgdL: near?.valueMgdL))
        }

        // Accompanying bolus.
        let boluses = insulin.filter {
            $0.doseContext != .basal && !$0.insulinType.isBasal
                && abs($0.timestamp.timeIntervalSince(mealTime)) <= bolusWindow
        }
        let bolusUnits = boluses.isEmpty ? nil : boluses.reduce(0) { $0 + $1.units }
        let bolusAt = boluses.min { abs($0.timestamp.timeIntervalSince(mealTime)) < abs($1.timestamp.timeIntervalSince(mealTime)) }?.timestamp

        return MealResponse(
            mealID: meal.id,
            mealTime: mealTime,
            mealType: meal.mealType,
            grams: meal.grams,
            windowHours: hours,
            baselineMgdL: baselineMgdL,
            peakMgdL: peakMgdL,
            minutesToPeak: minutesToPeak,
            returnMinutes: returnMinutes,
            excursionAUC: auc,
            inRangePercent: inRangePercent,
            bolusUnits: bolusUnits,
            bolusAt: bolusAt,
            points: points,
            markers: markers
        )
    }

    /// The most recent earlier meal of the same type with roughly comparable carbs
    /// (±25%), for a "vs last time" comparison. Nil when there's no good match.
    static func previousComparable(
        to meal: CarbEntry,
        among meals: [CarbEntry]
    ) -> CarbEntry? {
        let lower = meal.grams * 0.75
        let upper = meal.grams * 1.25
        return meals
            .filter { $0.id != meal.id
                   && $0.timestamp < meal.timestamp
                   && $0.mealType == meal.mealType
                   && $0.grams >= lower && $0.grams <= upper }
            .max { $0.timestamp < $1.timestamp }
    }
}
