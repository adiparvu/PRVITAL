import Foundation

/// Reduces a large glucose series to a chart-friendly point count.
///
/// A full CGM history spans tens of thousands of readings (≈288/day). Feeding
/// every raw point to Swift Charts emits one mark per reading and blows up the
/// SwiftUI view tree (a month ≈ 8.6k points, a year ≈ 105k), which stalls the
/// main thread. This keeps each time bucket's **min and max** reading, so the
/// downsampled curve preserves the highs and lows that matter clinically while
/// capping the mark count.
enum GlucoseDownsampler {

    /// Returns at most ~`maxPoints` readings from a time-sorted `readings` array,
    /// preserving per-bucket extremes. Returns the input unchanged when it is
    /// already small enough. Assumes `readings` is sorted ascending by timestamp.
    static func downsample(_ readings: [GlucoseReading], maxPoints: Int = 480) -> [GlucoseReading] {
        guard maxPoints > 4, readings.count > maxPoints else { return readings }

        // Two emitted points per bucket (the min and the max), so aim for half as
        // many buckets as the target point budget.
        let bucketCount = max(1, maxPoints / 2)
        let n = readings.count
        var result: [GlucoseReading] = []
        result.reserveCapacity(maxPoints + 2)

        for bucket in 0..<bucketCount {
            let start = bucket * n / bucketCount
            let end = (bucket + 1) * n / bucketCount
            guard start < end else { continue }
            let slice = readings[start..<end]
            guard let low = slice.min(by: { $0.valueMgdL < $1.valueMgdL }),
                  let high = slice.max(by: { $0.valueMgdL < $1.valueMgdL }) else { continue }
            // Emit the pair in timestamp order so the line stays monotonic in x.
            if low === high {
                result.append(low)
            } else if low.timestamp <= high.timestamp {
                result.append(low); result.append(high)
            } else {
                result.append(high); result.append(low)
            }
        }
        return result
    }
}
