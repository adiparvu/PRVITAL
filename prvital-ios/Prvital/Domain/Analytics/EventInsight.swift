import Foundation

/// How a logged event connects to the glucose around it — the reading just
/// before, the reading roughly `afterHours` later, and the insulin that was
/// already on board at the moment. It turns a flat log entry into a small story:
/// "134 → 96 over 2 h, with 1.2 U still active." Pure and deterministic.
struct EventInsight: Equatable, Sendable {
    /// Glucose (mg/dL) at or just before the event.
    var glucoseBefore: Double?
    /// Glucose (mg/dL) roughly `afterHours` after the event, once that time has passed.
    var glucoseAfter: Double?
    /// Insulin still active from *earlier* doses at the event moment (stacking) —
    /// excludes the event's own dose.
    var iobBefore: Double?
    /// How many minutes after the event the "after" reading was taken.
    var afterElapsedMinutes: Int?

    /// Change from before to after, when both are known.
    var deltaMgdL: Double? {
        guard let before = glucoseBefore, let after = glucoseAfter else { return nil }
        return after - before
    }

    var hasContext: Bool { glucoseBefore != nil || glucoseAfter != nil || (iobBefore ?? 0) >= 0.05 }

    static func make(
        eventDate: Date,
        excludingDoseID: UUID?,
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        bolus: BolusParameters,
        afterHours: Double = 2,
        matchWindow: TimeInterval = 30 * 60,
        now: Date = Date()
    ) -> EventInsight {
        var e = EventInsight()
        let active = readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }

        // Before: the nearest reading at or before the event, within the window.
        e.glucoseBefore = active.last {
            $0.timestamp <= eventDate && eventDate.timeIntervalSince($0.timestamp) <= matchWindow
        }?.valueMgdL

        // After: the reading nearest to (event + afterHours), within the window —
        // only once that time has actually passed.
        let afterTarget = eventDate.addingTimeInterval(afterHours * 3600)
        if now >= afterTarget.addingTimeInterval(-matchWindow),
           let afterReading = active
               .filter({ abs($0.timestamp.timeIntervalSince(afterTarget)) <= matchWindow })
               .min(by: { abs($0.timestamp.timeIntervalSince(afterTarget)) < abs($1.timestamp.timeIntervalSince(afterTarget)) }) {
            e.glucoseAfter = afterReading.valueMgdL
            e.afterElapsedMinutes = Int(afterReading.timestamp.timeIntervalSince(eventDate) / 60)
        }

        // Insulin already active at the event moment, from earlier doses only.
        if bolus.isValid {
            let prior = insulin.filter { $0.id != excludingDoseID }
            e.iobBefore = InsulinMath.activeInsulin(doses: prior, at: eventDate, parameters: bolus)
        }
        return e
    }
}
