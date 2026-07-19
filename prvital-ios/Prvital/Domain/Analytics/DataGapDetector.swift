import Foundation

/// Summary of gaps in the CGM trace — stretches where consecutive readings are
/// further apart than expected (a sensor warm-up, a dropout, or the phone being
/// out of range). Complements the coverage metric with the concrete longest gap.
struct GapStats: Equatable, Sendable {
    let gapCount: Int
    let longestGapMinutes: Double
    let totalGapMinutes: Double
}

/// Finds gaps between consecutive readings. Pure and deterministic: it walks the
/// time-ordered trace and records every interval longer than the threshold.
enum DataGapDetector {
    /// Consecutive readings more than this far apart count as a gap (minutes).
    static let defaultGapThresholdMinutes: Double = 30

    /// Returns the gap summary, or nil when there are fewer than two readings or
    /// no interval exceeds the threshold.
    static func analyze(
        _ readings: [GlucoseReading],
        gapThresholdMinutes: Double = defaultGapThresholdMinutes
    ) -> GapStats? {
        let ordered = readings.filter { $0.isActive }.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count > 1 else { return nil }

        let threshold = gapThresholdMinutes * 60
        var count = 0
        var longest: TimeInterval = 0
        var total: TimeInterval = 0
        for pair in zip(ordered, ordered.dropFirst()) {
            let delta = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            if delta > threshold {
                count += 1
                total += delta
                longest = max(longest, delta)
            }
        }

        guard count > 0 else { return nil }
        return GapStats(gapCount: count, longestGapMinutes: longest / 60, totalGapMinutes: total / 60)
    }
}
