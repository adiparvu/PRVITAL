import Foundation

/// A point on the hero wave — the glucose curve rendered tide-style on the
/// dashboard's first screen.
struct TidePoint: Equatable, Sendable {
    var date: Date
    var mgdL: Double
}

/// The pure geometry behind the dashboard's tide-style hero: where the current
/// value sits on the dial's gauge arc, where the target band lies, and which
/// points of the wave earn the peak/trough annotations. SwiftUI-free so every
/// rule is unit-testable.
enum TideHeroMath {
    /// The dial's scale, in mg/dL. Wide enough that every plausible reading has
    /// a position; values beyond it pin to the ends.
    static let gaugeLowerMgdL: Double = 40
    static let gaugeUpperMgdL: Double = 250

    /// Where a value sits on the gauge, as 0...1 across the scale. Clamped, so
    /// an extreme reading pins to an end instead of leaving the dial.
    static func gaugeFraction(mgdL: Double) -> Double {
        let span = gaugeUpperMgdL - gaugeLowerMgdL
        return min(max((mgdL - gaugeLowerMgdL) / span, 0), 1)
    }

    /// The target band's position on the gauge, as fractions. Degenerate or
    /// inverted thresholds collapse to nil rather than drawing a broken arc.
    static func bandFractions(lowerMgdL: Double, upperMgdL: Double) -> ClosedRange<Double>? {
        guard upperMgdL > lowerMgdL else { return nil }
        let lo = gaugeFraction(mgdL: lowerMgdL)
        let hi = gaugeFraction(mgdL: upperMgdL)
        guard hi > lo else { return nil }
        return lo...hi
    }

    /// The wave's annotated extremes: the highest and lowest reading of the
    /// window — the tide chart's "high tide / low tide" moments. When the window
    /// is flat (or too small to say anything), only the high survives; with
    /// fewer than three points neither is worth calling an extreme.
    static func extremes(of points: [TidePoint]) -> (high: TidePoint?, low: TidePoint?) {
        guard points.count >= 3 else { return (nil, nil) }
        guard let high = points.max(by: { $0.mgdL < $1.mgdL }),
              let low = points.min(by: { $0.mgdL < $1.mgdL }) else { return (nil, nil) }
        if high.mgdL == low.mgdL { return (high, nil) }
        return (high, low)
    }
}
