import Foundation

/// The user's personal therapy settings for the bolus **calculator**. All
/// glucose figures are mg/dL internally; the UI converts for display.
///
/// These are entered by the user from their own care plan — the app never
/// invents them — and the calculator stays hidden until `isEnabled` is set, so
/// no dose math is ever shown without the user opting in and providing values.
struct BolusParameters: Codable, Equatable, Sendable {
    /// Insulin-to-carb ratio: grams of carbohydrate covered by one unit (g/U).
    var carbRatio: Double = 10
    /// Correction (insulin-sensitivity) factor: mg/dL that one unit lowers (mg/dL·U).
    var correctionFactor: Double = 50
    /// Target glucose a correction aims for (mg/dL).
    var targetMgdL: Double = 110
    /// Duration of insulin action (hours) — how long a bolus keeps working.
    var durationHours: Double = 5
    /// Time from dose to peak activity (minutes).
    var peakMinutes: Double = 75
    /// A hard ceiling; a suggestion above this is clamped and flagged.
    var maxBolus: Double = 25
    /// The user must explicitly enable the calculator before it appears.
    var isEnabled: Bool = false

    static let `default` = BolusParameters()

    /// Whether the numbers are usable (positive divisors, sane curve shape).
    ///
    /// The exponential IOB model is only defined for a time-to-peak shorter than
    /// **half** the duration — at `peak == duration/2` the curve's `tau` term is
    /// infinite — so the guard requires `2·peak < duration`, not just `peak <
    /// duration`.
    var isValid: Bool {
        carbRatio > 0 && correctionFactor > 0 && durationHours > 0 &&
        peakMinutes > 0 && 2 * peakMinutes < durationHours * 60 && maxBolus > 0
    }
}

/// The transparent breakdown of a bolus suggestion, so the user sees exactly how
/// each part was derived rather than a single opaque number.
struct BolusEstimate: Equatable, Sendable {
    var carbBolus: Double = 0
    var correctionBolus: Double = 0
    var activeInsulin: Double = 0
    /// `max(0, carb + correction − IOB)`, clamped to `maxBolus`.
    var suggested: Double = 0
    var warnings: [String] = []
}

/// Pure insulin pharmacokinetics: insulin-on-board and a bolus suggestion.
///
/// IOB uses the exponential insulin-activity model (the curve used by Loop and
/// oref), parameterised by duration of action and time-to-peak, which fits
/// rapid-acting analogues far better than a straight linear decay. Everything
/// here is a deterministic function of its inputs — no clock, no storage — so it
/// is trivially testable and identical on every device.
enum InsulinMath {

    // MARK: Insulin on board

    /// The fraction (0…1) of a dose still active `minutes` after delivery, for
    /// the exponential curve with the given peak and total duration (minutes).
    static func remainingFraction(minutes t: Double, peak tp: Double, duration td: Double) -> Double {
        guard td > 0 else { return 0 }
        if t <= 0 { return 1 }
        if t >= td { return 0 }
        // The exponential model is defined only for peak < duration/2; at
        // peak == duration/2 the `tau` term is infinite. Outside that domain,
        // fall back to linear decay so IOB is never NaN or spuriously zero —
        // either of which would under-count insulin on board and over-suggest.
        guard tp > 0, tp < td / 2 else { return max(0, 1 - t / td) }

        // Exponential model (Loop / oref): tau and the normalising constants.
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))

        let iob = 1 - s * (1 - a) *
            ((t * t / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)
        return min(1, max(0, iob))
    }

    /// Total active insulin (units) from `doses` as of `date`, counting only
    /// rapid-acting (bolus) insulin — long-acting basal has different kinetics
    /// and is not part of bolus IOB.
    static func activeInsulin(
        doses: [InsulinDose],
        at date: Date,
        parameters: BolusParameters
    ) -> Double {
        let duration = parameters.durationHours * 60
        let peak = parameters.peakMinutes
        return doses.reduce(0) { total, dose in
            guard dose.insulinType == .rapidActing else { return total }
            let elapsed = date.timeIntervalSince(dose.timestamp) / 60
            guard elapsed >= 0, elapsed < duration else { return total }
            return total + dose.units * remainingFraction(minutes: elapsed, peak: peak, duration: duration)
        }
    }

    /// One dose still contributing to the IOB — what was injected, what's left
    /// of it right now, and when it runs out. The per-dose answer to "is this
    /// the correction from just now or what's left of lunch?".
    struct ActiveDose: Identifiable, Equatable, Sendable {
        let id: UUID
        let timestamp: Date
        /// Units injected.
        let units: Double
        /// Units still active at the evaluation instant.
        let remainingUnits: Double
        let context: InsulinDoseContext
        /// When this dose's duration of action ends.
        let endsAt: Date

        /// 0…1 of the dose already used up — drives the decay bar.
        var usedFraction: Double {
            units > 0 ? min(1, max(0, 1 - remainingUnits / units)) : 1
        }
    }

    /// The doses behind `activeInsulin`, newest first — same filter, same curve,
    /// just not summed. Doses with a negligible remainder (< 0.05 U) are
    /// dropped, matching the strip's own display threshold.
    static func activeDoses(
        doses: [InsulinDose],
        at date: Date,
        parameters: BolusParameters
    ) -> [ActiveDose] {
        let duration = parameters.durationHours * 60
        let peak = parameters.peakMinutes
        return doses.compactMap { dose -> ActiveDose? in
            guard dose.insulinType == .rapidActing else { return nil }
            let elapsed = date.timeIntervalSince(dose.timestamp) / 60
            guard elapsed >= 0, elapsed < duration else { return nil }
            let remaining = dose.units * remainingFraction(minutes: elapsed, peak: peak, duration: duration)
            guard remaining >= 0.05 else { return nil }
            return ActiveDose(
                id: dose.id, timestamp: dose.timestamp, units: dose.units,
                remainingUnits: remaining, context: dose.doseContext,
                endsAt: dose.timestamp.addingTimeInterval(duration * 60))
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Bolus suggestion

    /// A transparent bolus suggestion for `carbs` grams at the current glucose,
    /// given active insulin. Returns component parts and any safety warnings.
    ///
    /// This is a calculator, not a prescription: the result is only ever a
    /// starting point for the user's own judgement and their clinician's plan.
    static func suggestBolus(
        carbs: Double,
        currentMgdL: Double?,
        activeInsulin iob: Double,
        parameters p: BolusParameters,
        thresholds: GlucoseThresholds
    ) -> BolusEstimate {
        var estimate = BolusEstimate()
        estimate.activeInsulin = max(0, iob)

        guard p.isValid else {
            estimate.warnings.append("Set your carb ratio, correction factor and target first.")
            return estimate
        }

        estimate.carbBolus = max(0, carbs) / p.carbRatio

        if let currentMgdL {
            estimate.correctionBolus = (currentMgdL - p.targetMgdL) / p.correctionFactor
            if currentMgdL < thresholds.targetLower {
                estimate.warnings.append("Glucose is low — treat the low first; a meal bolus may need reducing or delaying.")
            }
        } else {
            estimate.warnings.append("No recent glucose — the correction part is not included.")
        }

        let raw = estimate.carbBolus + estimate.correctionBolus - estimate.activeInsulin
        var suggested = max(0, raw)

        if suggested > p.maxBolus {
            suggested = p.maxBolus
            estimate.warnings.append("Above your \(p.maxBolus.formatted()) U safety limit — clamped. Double-check before dosing.")
        }

        estimate.suggested = suggested
        return estimate
    }
}
