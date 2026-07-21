import Foundation

/// A single point on a chart worth calling out: a local or global maximum
/// ("peak") or minimum ("valley"), labeled directly on the curve the way tide
/// charts annotate their crests and troughs.
struct ChartExtreme: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case peak
        case valley
    }

    let date: Date
    let value: Double
    let kind: Kind

    /// Selection never returns two extremes at the same instant, so the date
    /// alone identifies an extreme.
    var id: Date { date }
}

/// Chooses which points of a time series deserve an on-curve label.
///
/// Selection rules (deterministic, pure — Foundation only):
/// 1. The window's global maximum and global minimum are always included
///    (the first occurrence wins when a value repeats). When the two coincide
///    on the same sample — a single point, or an entirely flat series — a
///    single extreme is returned, labeled as a peak.
/// 2. Up to `maximumAdditional` further local extremes join them, but only
///    "prominent" ones: an interior turning point whose value differs from
///    BOTH of its neighbouring turning points (window endpoints included) by
///    at least `prominenceThreshold` — default 25, in the same unit as the
///    values (mg/dL for glucose). Runs of equal consecutive values collapse
///    into one turning point, represented by the run's first sample.
/// 3. An added local extreme must lie at least `minimumSeparation` (default
///    45 minutes) from every extreme already chosen, so labels cannot
///    collide. Candidates are considered in descending prominence order
///    (ties broken by earlier date), and at most `maximumTotal` extremes are
///    returned in ascending date order.
enum ChartExtremes {

    static func find(
        in samples: [(date: Date, value: Double)],
        prominenceThreshold: Double = 25,
        minimumSeparation: TimeInterval = 45 * 60,
        maximumAdditional: Int = 2,
        maximumTotal: Int = 4
    ) -> [ChartExtreme] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.date < $1.date }

        // Global max / min — first occurrence when a value repeats.
        var maxIndex = 0
        var minIndex = 0
        for (i, sample) in sorted.enumerated() {
            if sample.value > sorted[maxIndex].value { maxIndex = i }
            if sample.value < sorted[minIndex].value { minIndex = i }
        }

        var selected = [
            ChartExtreme(date: sorted[maxIndex].date, value: sorted[maxIndex].value, kind: .peak)
        ]
        if minIndex != maxIndex, sorted[minIndex].date != sorted[maxIndex].date {
            selected.append(
                ChartExtreme(date: sorted[minIndex].date, value: sorted[minIndex].value, kind: .valley)
            )
        }

        // Collapse runs of equal consecutive values (plateaus) so a turning
        // point is a genuine change of direction; the run's first sample
        // represents it.
        var compressed: [(index: Int, value: Double)] = []
        for (i, sample) in sorted.enumerated() where compressed.last?.value != sample.value {
            compressed.append((index: i, value: sample.value))
        }

        // Interior turning points. Consecutive compressed values always
        // differ, so a direction change is a clean peak or valley.
        var turns: [(index: Int, value: Double, kind: ChartExtreme.Kind)] = []
        if compressed.count >= 3 {
            for j in 1..<(compressed.count - 1) {
                let previous = compressed[j - 1].value
                let current = compressed[j].value
                let next = compressed[j + 1].value
                if current > previous, current > next {
                    turns.append((index: compressed[j].index, value: current, kind: .peak))
                } else if current < previous, current < next {
                    turns.append((index: compressed[j].index, value: current, kind: .valley))
                }
            }
        }

        // Prominence: how far a turning point rises above (peak) or drops
        // below (valley) its neighbouring turning points, endpoints included.
        struct Candidate {
            let index: Int
            let kind: ChartExtreme.Kind
            let prominence: Double
        }
        var candidates: [Candidate] = []
        if let firstValue = compressed.first?.value, let lastValue = compressed.last?.value {
            for (k, turn) in turns.enumerated() {
                let left = k == 0 ? firstValue : turns[k - 1].value
                let right = k == turns.count - 1 ? lastValue : turns[k + 1].value
                let prominence = turn.kind == .peak
                    ? min(turn.value - left, turn.value - right)
                    : min(left - turn.value, right - turn.value)
                candidates.append(Candidate(index: turn.index, kind: turn.kind, prominence: prominence))
            }
        }

        let ranked = candidates
            .filter { $0.index != maxIndex && $0.index != minIndex && $0.prominence >= prominenceThreshold }
            .sorted {
                $0.prominence == $1.prominence
                    ? sorted[$0.index].date < sorted[$1.index].date
                    : $0.prominence > $1.prominence
            }

        var added = 0
        for candidate in ranked where added < maximumAdditional && selected.count < maximumTotal {
            let sample = sorted[candidate.index]
            let clear = selected.allSatisfy {
                abs($0.date.timeIntervalSince(sample.date)) >= minimumSeparation
            }
            guard clear else { continue }
            selected.append(ChartExtreme(date: sample.date, value: sample.value, kind: candidate.kind))
            added += 1
        }

        return selected.sorted { $0.date < $1.date }
    }
}
