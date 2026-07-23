import Foundation

/// Average glucose bucketed by weekday × time-of-day — the data behind the
/// Analize heatmap, so a glance reveals which windows run high or low (e.g.
/// "Tuesday evenings"). Weekdays are indexed 0 = Sunday … 6 = Saturday (the
/// view reorders them to the locale's first weekday). Pure and deterministic.
struct GlucoseHeatmap: Equatable, Sendable {
    /// How many equal time-of-day blocks the 24 h are split into (8 → 3-hour blocks).
    let blocksPerDay: Int
    /// `averages[block][weekday]` in mg/dL, or nil when that bucket has no readings.
    let averages: [[Double?]]

    var hasData: Bool { averages.contains { $0.contains { $0 != nil } } }

    static func build(_ readings: [GlucoseReading], blocksPerDay: Int = 8,
                      calendar: Calendar = .current) -> GlucoseHeatmap {
        let blocks = max(1, min(blocksPerDay, 24))
        let blockHours = max(1, 24 / blocks)
        var sums = Array(repeating: Array(repeating: 0.0, count: 7), count: blocks)
        var counts = Array(repeating: Array(repeating: 0, count: 7), count: blocks)

        for r in readings where r.isActive {
            let comps = calendar.dateComponents([.weekday, .hour], from: r.timestamp)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            let col = (weekday - 1) % 7                 // 1=Sun … 7=Sat → 0…6
            let block = min(hour / blockHours, blocks - 1)
            sums[block][col] += r.valueMgdL
            counts[block][col] += 1
        }

        var averages = Array(repeating: Array(repeating: Double?.none, count: 7), count: blocks)
        for b in 0..<blocks {
            for c in 0..<7 where counts[b][c] > 0 {
                averages[b][c] = sums[b][c] / Double(counts[b][c])
            }
        }
        return GlucoseHeatmap(blocksPerDay: blocks, averages: averages)
    }
}
