import Foundation

/// One time-of-day bucket of the Ambulatory Glucose Profile: the glucose
/// percentiles across every day in the period, at that time of day. All mg/dL.
struct AGPBucket: Identifiable, Equatable, Sendable {
    let minutesOfDay: Int   // bucket centre, 0...1440
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
    var id: Int { minutesOfDay }
}

/// Builds the AGP by collapsing all readings onto a single 24-hour day and
/// computing per-bucket percentiles — the standard clinical "modal day" view.
enum AGPAggregator {
    static func buckets(
        _ readings: [GlucoseReading],
        binMinutes: Int = 60,
        calendar: Calendar = .current
    ) -> [AGPBucket] {
        let active = readings.filter(\.isActive)
        guard !active.isEmpty, binMinutes > 0 else { return [] }

        var bins: [Int: [Double]] = [:]
        for reading in active {
            let comps = calendar.dateComponents([.hour, .minute], from: reading.timestamp)
            let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            bins[minuteOfDay / binMinutes, default: []].append(reading.valueMgdL)
        }

        return bins.keys.sorted().map { index in
            let sorted = bins[index]!.sorted()
            return AGPBucket(
                minutesOfDay: index * binMinutes + binMinutes / 2,
                p10: percentile(sorted, 0.10),
                p25: percentile(sorted, 0.25),
                p50: percentile(sorted, 0.50),
                p75: percentile(sorted, 0.75),
                p90: percentile(sorted, 0.90)
            )
        }
    }

    /// Linear-interpolation percentile over a pre-sorted array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = Int(rank.rounded(.up))
        let fraction = rank - Double(low)
        return sorted[low] + (sorted[high] - sorted[low]) * fraction
    }
}
