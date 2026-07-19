import Foundation

/// A rebound high: a low episode followed, within a short window and before the
/// next low, by a climb above the target range — the classic sign of
/// over-treating a hypo.
struct ReboundEvent: Identifiable {
    let lowTime: Date
    let lowMgdL: Double
    let highTime: Date
    let highMgdL: Double

    /// Minutes from the low's nadir to the rebound high.
    var minutesLowToHigh: Int { Int((highTime.timeIntervalSince(lowTime) / 60).rounded()) }

    var id: Date { lowTime }
}

/// Finds rebound highs after lows. Pure and deterministic: it walks the
/// time-ordered trace, and for each completed low episode (a run below the
/// target floor that then recovers) looks forward — up to `withinMinutes` and
/// only until the next low — for a peak above the target ceiling.
enum ReboundDetector {
    static let defaultWindowMinutes: Double = 120

    static func detect(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        withinMinutes: Double = defaultWindowMinutes
    ) -> [ReboundEvent] {
        let ordered = readings.filter { $0.isActive }.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count > 1 else { return [] }

        let lower = thresholds.targetLower
        let upper = thresholds.targetUpper
        let window = withinMinutes * 60

        var events: [ReboundEvent] = []
        var i = 0
        let n = ordered.count
        while i < n {
            guard ordered[i].valueMgdL < lower else { i += 1; continue }

            // Walk the low run, tracking its nadir.
            var nadirValue = ordered[i].valueMgdL
            var nadirTime = ordered[i].timestamp
            while i < n, ordered[i].valueMgdL < lower {
                if ordered[i].valueMgdL < nadirValue {
                    nadirValue = ordered[i].valueMgdL
                    nadirTime = ordered[i].timestamp
                }
                i += 1
            }
            guard i < n else { break } // ended while still low → no recovery, no rebound

            // Look forward for a peak above range, until the window closes or the
            // next low begins.
            let recoveryTime = ordered[i].timestamp
            var peakValue: Double?
            var peakTime = recoveryTime
            var j = i
            while j < n, ordered[j].timestamp <= recoveryTime.addingTimeInterval(window) {
                let v = ordered[j].valueMgdL
                if v < lower { break }
                if v > upper, peakValue == nil || v > peakValue! {
                    peakValue = v
                    peakTime = ordered[j].timestamp
                }
                j += 1
            }
            if let peak = peakValue {
                events.append(ReboundEvent(lowTime: nadirTime, lowMgdL: nadirValue, highTime: peakTime, highMgdL: peak))
            }
        }
        return events
    }
}
