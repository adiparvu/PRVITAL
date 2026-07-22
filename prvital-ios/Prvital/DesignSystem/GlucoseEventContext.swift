import SwiftUI
import Foundation

/// The glucose reading nearest a logged event (an injection, a meal) — its value
/// with a zone tint and a trend arrow — so an event can show where your glucose
/// was at that moment. Built from the CGM history already stored (e.g. imported
/// from Clarity); no new data source needed.
struct GlucoseEventContext {
    let text: String
    let unitText: String
    let trendSymbol: String
    let color: Color
    let accessibility: String

    /// The nearest active reading to `time` within `tolerance`, from
    /// `sortedReadings` (ascending by timestamp). Uses binary search, so matching
    /// many events against a long history stays cheap.
    static func nearest(to time: Date, in sortedReadings: [GlucoseReading],
                        unit: GlucoseUnit, thresholds: GlucoseThresholds,
                        tolerance: TimeInterval = 20 * 60) -> GlucoseEventContext? {
        guard !sortedReadings.isEmpty else { return nil }
        var lo = 0, hi = sortedReadings.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedReadings[mid].timestamp < time { lo = mid + 1 } else { hi = mid }
        }
        var bestIdx = lo
        var bestDelta = abs(sortedReadings[lo].timestamp.timeIntervalSince(time))
        if lo > 0 {
            let d = abs(sortedReadings[lo - 1].timestamp.timeIntervalSince(time))
            if d < bestDelta { bestDelta = d; bestIdx = lo - 1 }
        }
        guard bestDelta <= tolerance else { return nil }
        let nearest = sortedReadings[bestIdx]
        let symbol = nearest.trend?.symbol ?? trendSymbol(in: sortedReadings, at: bestIdx)
        let value = GlucoseFormatting.string(mgdL: nearest.valueMgdL, unit: unit)
        return GlucoseEventContext(
            text: value,
            unitText: unit.rawValue,
            trendSymbol: symbol,
            color: thresholds.zone(forMgdL: nearest.valueMgdL).color,
            accessibility: String(localized: "\(value) \(unit.rawValue) at the time")
        )
    }

    /// A 5-way CGM trend arrow inferred from the slope between the nearest reading
    /// and one 8–25 minutes earlier, when the reading has no stored trend.
    private static func trendSymbol(in sorted: [GlucoseReading], at index: Int) -> String {
        let nearest = sorted[index]
        guard let prior = sorted[..<index].last(where: {
            let dt = nearest.timestamp.timeIntervalSince($0.timestamp)
            return dt >= 8 * 60 && dt <= 25 * 60
        }) else { return "arrow.right" }
        let minutes = nearest.timestamp.timeIntervalSince(prior.timestamp) / 60
        guard minutes > 0 else { return "arrow.right" }
        let rate = (nearest.valueMgdL - prior.valueMgdL) / minutes
        switch rate {
        case ..<(-2.0): return "arrow.down"
        case -2.0 ..< -1.0: return "arrow.down.right"
        case -1.0 ..< 1.0: return "arrow.right"
        case 1.0 ..< 2.0: return "arrow.up.right"
        default: return "arrow.up"
        }
    }

    /// A small tinted chip — drop + value + trend arrow — for use in list rows.
    @ViewBuilder var chip: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill").font(.system(size: 9))
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
            Image(systemName: trendSymbol).font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .accessibilityLabel(accessibility)
    }
}
