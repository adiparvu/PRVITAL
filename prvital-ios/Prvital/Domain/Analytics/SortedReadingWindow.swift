import Foundation

/// Window lookups over a time-ordered reading array.
///
/// The impact analyzers ask "which readings fall around this meal / session?"
/// once per event. Answering that with `filter` walks — and copies — the whole
/// array every single time: a year of meals behind a year of CGM is on the
/// order of hundreds of millions of comparisons and thousands of full-array
/// allocations, which is exactly what made Analyze crawl on Month and Year.
///
/// The array is already sorted by timestamp, so a binary search finds each
/// window's bounds in log n and returns a slice that copies nothing.
extension Array where Element == GlucoseReading {

    /// Readings with `lower <= timestamp <= upper`.
    /// The array must be sorted ascending by timestamp.
    func readings(from lower: Date, through upper: Date) -> ArraySlice<GlucoseReading> {
        slice(startingWhere: { $0.timestamp >= lower }, endingWhere: { $0.timestamp > upper })
    }

    /// Readings with `lower < timestamp <= upper`.
    /// The array must be sorted ascending by timestamp.
    func readings(after lower: Date, through upper: Date) -> ArraySlice<GlucoseReading> {
        slice(startingWhere: { $0.timestamp > lower }, endingWhere: { $0.timestamp > upper })
    }

    private func slice(
        startingWhere isAtOrAfterStart: (Element) -> Bool,
        endingWhere isPastEnd: (Element) -> Bool
    ) -> ArraySlice<GlucoseReading> {
        let start = partitionPoint(isAtOrAfterStart)
        let end = partitionPoint(isPastEnd)
        guard start < end else { return self[start..<start] }
        return self[start..<end]
    }

    /// The first index where `predicate` turns true. Valid because any
    /// monotone timestamp comparison partitions a time-ordered array.
    private func partitionPoint(_ predicate: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = low + (high - low) / 2
            if predicate(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
