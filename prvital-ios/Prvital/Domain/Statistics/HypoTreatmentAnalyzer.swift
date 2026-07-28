import Foundation

/// What the user's own low treatments actually do — the personal answer to
/// "is 12 g enough for me?". Built from the rule-of-15 carb entries (tagged
/// "feeling low") and the glucose curve around each one. Informational only:
/// it reports what happened, never what to take.
struct HypoTreatmentStats: Equatable, Sendable {
    /// Logged treatments in the window.
    var treatmentCount = 0
    /// The user's typical (median) grams per treatment.
    var typicalGrams: Double = 0
    /// Mean rise (mg/dL) from just before a treatment to ~15–25 min after;
    /// nil when no treatment had usable readings on both sides.
    var averageRiseMgdL: Double?
    /// How many treatments had that before/after pair to measure.
    var risesMeasured = 0
    /// Distinct low episodes (treatments < 45 min apart share one episode).
    var episodes = 0
    /// Episodes that needed only a single round.
    var resolvedInOneRound = 0
}

enum HypoTreatmentAnalyzer {

    /// Below this many treatments the numbers are anecdotes, not statistics.
    static let minimumTreatments = 3
    /// Treatments closer together than this belong to the same low episode.
    static let episodeGapMinutes = 45.0

    static func analyze(
        readings: [GlucoseReading],
        carbs: [CarbEntry]
    ) -> HypoTreatmentStats? {
        let treatments = carbs
            .filter { $0.tags.contains(.hypoFeeling) }
            .sorted { $0.timestamp < $1.timestamp }
        guard treatments.count >= minimumTreatments else { return nil }

        var stats = HypoTreatmentStats()
        stats.treatmentCount = treatments.count

        let grams = treatments.map(\.grams).sorted()
        stats.typicalGrams = grams[grams.count / 2]

        // The rise each treatment produced: nearest reading just before it vs
        // the reading closest to the rule's own recheck point (~18 min after).
        let active = readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }
        var rises: [Double] = []
        for treatment in treatments {
            let t = treatment.timestamp
            let baseline = active
                .filter { $0.timestamp >= t.addingTimeInterval(-20 * 60)
                       && $0.timestamp <= t.addingTimeInterval(3 * 60) }
                .min { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) }
            let target = t.addingTimeInterval(18 * 60)
            let response = active
                .filter { $0.timestamp >= t.addingTimeInterval(12 * 60)
                       && $0.timestamp <= t.addingTimeInterval(30 * 60) }
                .min { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) }
            if let baseline, let response {
                rises.append(response.valueMgdL - baseline.valueMgdL)
            }
        }
        stats.risesMeasured = rises.count
        stats.averageRiseMgdL = rises.isEmpty ? nil : rises.reduce(0, +) / Double(rises.count)

        // Episodes: consecutive treatments < 45 min apart are one low.
        var episodeSizes: [Int] = []
        var currentSize = 0
        var lastTime: Date?
        for treatment in treatments {
            if let lastTime,
               treatment.timestamp.timeIntervalSince(lastTime) < episodeGapMinutes * 60 {
                currentSize += 1
            } else {
                if currentSize > 0 { episodeSizes.append(currentSize) }
                currentSize = 1
            }
            lastTime = treatment.timestamp
        }
        if currentSize > 0 { episodeSizes.append(currentSize) }
        stats.episodes = episodeSizes.count
        stats.resolvedInOneRound = episodeSizes.filter { $0 == 1 }.count

        return stats
    }
}
