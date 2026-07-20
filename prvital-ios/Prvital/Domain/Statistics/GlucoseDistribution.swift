import Foundation

/// One bar of the glucose distribution histogram: a mg/dL bin and how many
/// readings fell in it.
struct DistributionBin: Identifiable {
    let lowerMgdL: Double
    let upperMgdL: Double
    let count: Int

    var id: Double { lowerMgdL }
    var midpoint: Double { (lowerMgdL + upperMgdL) / 2 }
}

/// Bins a CGM trace into a glucose distribution histogram. Pure and
/// deterministic: readings are counted into fixed-width mg/dL bins, with values
/// outside the range clamped into the first / last bin so nothing is dropped.
enum GlucoseDistribution {
    static func bins(
        _ readings: [GlucoseReading],
        binWidth: Double = 20,
        lowerBound: Double = 40,
        upperBound: Double = 300
    ) -> [DistributionBin] {
        let active = readings.filter { $0.isActive }
        guard !active.isEmpty, binWidth > 0, upperBound > lowerBound else { return [] }

        let binCount = Int(((upperBound - lowerBound) / binWidth).rounded(.up))
        var counts = Array(repeating: 0, count: binCount)
        for reading in active {
            let raw = Int(((reading.valueMgdL - lowerBound) / binWidth).rounded(.down))
            let index = min(max(raw, 0), binCount - 1)
            counts[index] += 1
        }

        return (0..<binCount).map { i in
            let lower = lowerBound + Double(i) * binWidth
            return DistributionBin(lowerMgdL: lower, upperMgdL: lower + binWidth, count: counts[i])
        }
    }
}
