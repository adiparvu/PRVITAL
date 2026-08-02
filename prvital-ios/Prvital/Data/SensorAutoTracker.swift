import Foundation
import SwiftData

/// Starts sensor sessions BY ITSELF wherever a real signal exists, so the
/// countdown keeps running without the user logging anything (device request:
/// "where possible, it should add itself").
///
/// Two signals, in order of trust:
///  1. **LibreLinkUp tells us outright.** The graph payload carries the current
///     sensor's serial number and activation timestamp. The Libre client drops
///     them into `LibreSensorSignal` on every fetch; a serial we haven't
///     imported yet becomes a session with the EXACT insertion time.
///  2. **A replacement-shaped gap.** Dexcom Share and Apple Health expose no
///     session start, so once the tracked sensor has expired, a reading gap at
///     least one warm-up long — resuming near or after expiry — reads as "old
///     sensor off, new sensor warmed up": the next session starts
///     automatically with the same kind, backdated by the warm-up.
enum SensorAutoTracker {

    // MARK: Restart heuristic (pure, tested)

    struct AutoStart: Equatable {
        let kind: SensorKind
        let startDate: Date
    }

    /// Decides whether an expired session should roll into a new one of the
    /// same kind. `readingDates` is ascending. Conservative on purpose: it
    /// needs the old sensor to be past expiry AND a gap of at least one
    /// warm-up whose resume lands near or after that expiry — an ordinary
    /// signal dropout mid-wear never qualifies.
    static func evaluateRestart(
        lastKind: SensorKind,
        lastStart: Date,
        readingDates: [Date],
        now: Date
    ) -> AutoStart? {
        let expiry = lastStart.addingTimeInterval(lastKind.lifetime)
        guard now > expiry else { return nil }

        // Sensor changes rarely wait for the final minute — accept a resume
        // from half a day before expiry onward.
        let window = expiry.addingTimeInterval(-12 * 3600)
        let gap = max(lastKind.warmup, 25 * 60)

        var previous: Date?
        var resume: Date?
        for date in readingDates {
            if let previous, date.timeIntervalSince(previous) >= gap, date > window {
                resume = date   // keep the LAST qualifying gap — the freshest change
            }
            previous = date
        }
        guard let resume else { return nil }

        let start = resume.addingTimeInterval(-lastKind.warmup)
        guard start > lastStart.addingTimeInterval(3600) else { return nil }
        return AutoStart(kind: lastKind, startDate: start)
    }

    // MARK: Importer

    /// Consumes both signals. Cheap by design: one `fetchLimit == 1` session
    /// fetch always; the bounded readings fetch only once the tracked sensor
    /// has actually expired. Safe to call on every sync change.
    @MainActor
    static func run(context: ModelContext, now: Date = Date()) {
        var descriptor = FetchDescriptor<SensorSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor))?.first

        // 1) Exact — LibreLinkUp reported the worn sensor.
        if let pending = LibreSensorSignal.pending(), pending.activatedAt <= now {
            // Reuse the Libre model the user last tracked; a first-ever
            // session defaults to Libre 3 (the LibreLinkUp mainstay).
            let kind: SensorKind = (last?.kind.isLibre == true) ? last!.kind : .freeStyleLibre3
            if last == nil || pending.activatedAt > last!.startDate.addingTimeInterval(3600) {
                let session = SensorSession(startDate: pending.activatedAt, kind: kind)
                context.insert(session)
                SensorExpiryScheduler.reschedule(expiryDate: session.expiryDate,
                                                 sensorName: kind.displayName)
                try? context.save()
            }
            // Mark consumed either way — an older serial must not retry forever.
            LibreSensorSignal.markImported(serial: pending.serial)
            return
        }

        // 2) Heuristic — the tracked sensor expired and readings resumed
        //    after a replacement-sized silence.
        guard let last, now > last.expiryDate else { return }
        let cutoff = last.expiryDate.addingTimeInterval(-24 * 3600)
        let readingsDescriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let dates = ((try? context.fetch(readingsDescriptor)) ?? []).map(\.timestamp)
        if let auto = evaluateRestart(lastKind: last.kind, lastStart: last.startDate,
                                      readingDates: dates, now: now) {
            context.insert(SensorSession(startDate: auto.startDate, kind: auto.kind))
            try? context.save()
        }
    }
}
