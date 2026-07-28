import Foundation

/// Persisted memory for the missed-bolus nudge: which carb entries were already
/// reminded about, and when the last "rising without a bolus" fired.
struct MissedBolusState: Codable, Equatable, Sendable {
    var notifiedCarbIDs: [String] = []
    var lastRiseNotifiedAt: Date?
    static let empty = MissedBolusState()
}

/// What to say when a bolus looks forgotten.
struct MissedBolusAlert: Equatable, Sendable {
    enum Kind: String, Sendable {
        /// A meal was logged and no bolus accompanies it.
        case loggedMeal
        /// CGM shows a fast meal-sized climb with nothing logged at all.
        case risingUnlogged
    }
    let kind: Kind
    /// The meal's grams (loggedMeal only).
    var grams: Double?
    /// Minutes since the meal was logged (loggedMeal only).
    var minutesAgo: Int?
}

/// Decides whether a bolus looks forgotten. Pure — the service owns state
/// persistence and delivery. Two independent detectors:
///
/// 1. **Logged meal, no bolus**: a meal-sized carb entry is 25–90 minutes old
///    and no bolus exists from 45 min before it to now. The InPen pitch,
///    without the smart pen: by 25 minutes past the meal, a dose that was
///    taken is almost always already logged (or synced), so a gentle nudge is
///    warranted; past 90 minutes it's stale advice and stays quiet.
/// 2. **Fast unlogged climb**: glucose rose ≥ 55 mg/dL within ~45 minutes to
///    above 180 with no bolus in 90 min and no carbs logged in 2 h. The rate
///    requirement keeps slow drifts (dawn phenomenon, stress) from firing —
///    those belong to the pattern insights, not a push notification.
enum MissedBolusEvaluator {

    struct CarbEvent: Sendable {
        let id: String
        let timestamp: Date
        let grams: Double
    }
    struct DoseEvent: Sendable {
        let timestamp: Date
        let isBolus: Bool
    }
    struct Point: Sendable {
        let timestamp: Date
        let mgdL: Double
    }

    static let minMealGrams = 15.0
    static let mealGraceMinutes = 25.0
    static let mealExpiryMinutes = 90.0
    static let preBolusMinutes = 45.0
    static let riseThresholdMgdL = 55.0
    static let riseWindowMinutes = 50.0
    static let riseFloorMgdL = 180.0
    static let riseCooldownMinutes = 120.0
    /// Cap on the remembered carb-entry ids (oldest dropped first).
    static let rememberedIDs = 40

    static func decide(
        carbs: [CarbEvent],
        doses: [DoseEvent],
        points: [Point],
        state: MissedBolusState,
        now: Date
    ) -> (alert: MissedBolusAlert?, state: MissedBolusState) {
        var state = state
        let boluses = doses.filter(\.isBolus)

        // 1 — a meal old enough to expect its bolus, young enough to matter.
        let candidates = carbs
            .filter { $0.grams >= minMealGrams }
            .filter { !state.notifiedCarbIDs.contains($0.id) }
            .filter {
                let age = now.timeIntervalSince($0.timestamp) / 60
                return age >= mealGraceMinutes && age <= mealExpiryMinutes
            }
            .sorted { $0.timestamp < $1.timestamp }
        for meal in candidates {
            let covered = boluses.contains {
                $0.timestamp >= meal.timestamp.addingTimeInterval(-preBolusMinutes * 60)
                    && $0.timestamp <= now
            }
            if covered {
                // Mark it so an even later dose doesn't re-open the question.
                state.notifiedCarbIDs.append(meal.id)
                continue
            }
            state.notifiedCarbIDs.append(meal.id)
            state.notifiedCarbIDs = Array(state.notifiedCarbIDs.suffix(rememberedIDs))
            let minutes = Int((now.timeIntervalSince(meal.timestamp) / 60).rounded())
            return (MissedBolusAlert(kind: .loggedMeal, grams: meal.grams, minutesAgo: minutes), state)
        }
        state.notifiedCarbIDs = Array(state.notifiedCarbIDs.suffix(rememberedIDs))

        // 2 — a meal-sized climb with nothing logged.
        if let current = points.max(by: { $0.timestamp < $1.timestamp }),
           now.timeIntervalSince(current.timestamp) <= 15 * 60,
           current.mgdL >= riseFloorMgdL {
            let windowStart = current.timestamp.addingTimeInterval(-riseWindowMinutes * 60)
            // The lowest reading inside the window is the launch point of the climb.
            let launch = points
                .filter { $0.timestamp >= windowStart && $0.timestamp < current.timestamp }
                .min(by: { $0.mgdL < $1.mgdL })
            let cooledDown = state.lastRiseNotifiedAt.map {
                now.timeIntervalSince($0) >= riseCooldownMinutes * 60
            } ?? true
            let recentBolus = boluses.contains { now.timeIntervalSince($0.timestamp) <= 90 * 60 }
            let recentCarbs = carbs.contains { now.timeIntervalSince($0.timestamp) <= 120 * 60 }
            if let launch, current.mgdL - launch.mgdL >= riseThresholdMgdL,
               cooledDown, !recentBolus, !recentCarbs {
                state.lastRiseNotifiedAt = now
                return (MissedBolusAlert(kind: .risingUnlogged), state)
            }
        }

        return (nil, state)
    }
}
