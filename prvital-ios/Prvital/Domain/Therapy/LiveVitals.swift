import Foundation

/// The "how am I right now?" vitals shown under the dashboard glucose ring:
/// insulin- and carbs-on-board plus the small live timings — since the last
/// bolus, until active insulin clears, until the next CGM reading. Pure and
/// deterministic so it can be unit-tested and reused by the widget and watch.
struct LiveVitals: Equatable, Sendable {
    /// Insulin on board (units); 0 when there's none or the bolus setup is invalid.
    var insulinOnBoard: Double = 0
    /// Carbs on board (grams).
    var carbsOnBoard: Double = 0
    /// Minutes since the most recent still-active bolus; nil when there's none.
    var minutesSinceBolus: Int?
    /// Minutes until active insulin clears (last contributing dose + duration of
    /// action); nil when nothing is active.
    var minutesToInsulinClear: Int?
    /// Minutes until the next CGM reading is expected; nil for non-CGM sources or
    /// when the last reading is too old for a scheduled next one to apply.
    var minutesToNextReading: Int?
    /// The instant that next reading is expected — lets the dashboard tick a
    /// live seconds countdown over the final minute.
    var nextReadingAt: Date?
    /// The per-dose story behind `insulinOnBoard`, newest first — so two
    /// overlapping boluses (lunch still tailing + a fresh correction) can be
    /// told apart instead of hiding inside one summed number.
    var activeDoses: [InsulinMath.ActiveDose] = []

    var hasInsulinOnBoard: Bool { insulinOnBoard >= 0.05 }
    var hasCarbsOnBoard: Bool { carbsOnBoard >= 0.5 }

    /// Builds the vitals from the raw therapy records. `cgmCadenceMinutes` is the
    /// expected reading interval (≈5 min for Dexcom/Libre); `sourceIsCGM` gates the
    /// next-reading estimate so a fingerstick doesn't imply a scheduled reading.
    static func make(
        latestReadingAt: Date?,
        sourceIsCGM: Bool,
        cgmCadenceMinutes: Double,
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        bolus: BolusParameters,
        now: Date = Date()
    ) -> LiveVitals {
        var v = LiveVitals()
        v.insulinOnBoard = bolus.isValid
            ? InsulinMath.activeInsulin(doses: insulin, at: now, parameters: bolus) : 0
        if bolus.isValid {
            v.activeDoses = InsulinMath.activeDoses(doses: insulin, at: now, parameters: bolus)
        }
        v.carbsOnBoard = CarbMath.carbsOnBoard(entries: carbs, at: now)

        let diaSeconds = bolus.durationHours * 3600
        if diaSeconds > 0 {
            // Rapid-acting only — the same doses `InsulinMath.activeInsulin`
            // counts. A basal dose must never drive this timer: it works for
            // ~a day in the background and is deliberately not part of the
            // IOB, so "insulin ends" restarting after a basal shot (with the
            // BOLUS duration, of all things) read as a bug.
            let activeDoses = insulin.filter {
                $0.insulinType == .rapidActing
                    && $0.timestamp <= now && now.timeIntervalSince($0.timestamp) < diaSeconds
            }
            // Active insulin clears when the latest-starting active dose reaches its
            // duration of action — matching the doses that produce the IOB above.
            if v.hasInsulinOnBoard,
               let clearAt = activeDoses.map({ $0.timestamp.addingTimeInterval(diaSeconds) }).max(),
               clearAt > now {
                v.minutesToInsulinClear = Int((clearAt.timeIntervalSince(now) / 60).rounded(.up))
            }
            // Time since the most recent still-active bolus (rapid-acting).
            if let lastBolus = insulin.filter({
                !$0.insulinType.isBasal && $0.timestamp <= now
                    && now.timeIntervalSince($0.timestamp) < diaSeconds
            }).max(by: { $0.timestamp < $1.timestamp }) {
                v.minutesSinceBolus = Int(now.timeIntervalSince(lastBolus.timestamp) / 60)
            }
        }

        if sourceIsCGM, cgmCadenceMinutes > 0, let latestReadingAt {
            let cadence = cgmCadenceMinutes * 60
            // Only within a reasonable window of the last reading; otherwise the
            // stream is stale and no scheduled next reading applies.
            if now.timeIntervalSince(latestReadingAt) <= cadence * 2 {
                let expected = latestReadingAt.addingTimeInterval(cadence)
                let secs = expected.timeIntervalSince(now)
                if secs > 0 {
                    v.minutesToNextReading = Int((secs / 60).rounded(.up))
                    v.nextReadingAt = expected
                }
            }
        }
        return v
    }
}
