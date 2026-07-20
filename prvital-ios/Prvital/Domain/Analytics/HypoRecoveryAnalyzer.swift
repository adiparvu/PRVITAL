import Foundation

/// How quickly lows are resolved: the number of low episodes that recovered and
/// the average time from the first below-range reading back up into range.
struct HypoRecoveryStats: Equatable, Sendable {
    let episodeCount: Int
    let averageMinutes: Double
}

/// Measures low-to-recovery time. Pure and deterministic: it walks the
/// time-ordered trace, and for each low episode that returns to range records
/// the elapsed time from the first below-range reading to the first back in
/// range. Episodes that never recover within the data are not counted.
enum HypoRecoveryAnalyzer {
    static func analyze(_ readings: [GlucoseReading], thresholds: GlucoseThresholds) -> HypoRecoveryStats? {
        let ordered = readings.filter { $0.isActive }.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count > 1 else { return nil }

        let lower = thresholds.targetLower
        var durations: [TimeInterval] = []
        var i = 0
        let n = ordered.count
        while i < n {
            guard ordered[i].valueMgdL < lower else { i += 1; continue }

            let lowStart = ordered[i].timestamp
            while i < n, ordered[i].valueMgdL < lower { i += 1 }
            guard i < n else { break } // never recovered
            durations.append(ordered[i].timestamp.timeIntervalSince(lowStart))
        }

        guard !durations.isEmpty else { return nil }
        let averageMinutes = durations.reduce(0, +) / Double(durations.count) / 60
        return HypoRecoveryStats(episodeCount: durations.count, averageMinutes: averageMinutes)
    }
}
