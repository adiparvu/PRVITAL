import Foundation

/// The strength and direction of the association between a daily Apple Health
/// metric (steps, sleep, HRV) and daily *average glucose*, over the days both
/// were recorded. Pure and unit-testable — the view layer turns it into a card.
///
/// A **negative** coefficient means "more of the metric, lower glucose" — the
/// generally favourable direction for all three metrics (more movement, more
/// sleep, better recovery). This is an *association*, never proof of cause.
struct HealthGlucoseCorrelation: Sendable, Identifiable {
    enum Kind: String, Sendable { case steps, sleep, hrv }

    let kind: Kind
    /// Pearson correlation coefficient, clamped to -1…1.
    let coefficient: Double
    /// Number of paired days behind the estimate.
    let sampleSize: Int

    var id: String { kind.rawValue }

    /// `true` when the metric and lower glucose move together — the favourable
    /// direction to surface in green.
    var favourable: Bool { coefficient < 0 }

    enum Strength: Sendable { case negligible, weak, moderate, strong }
    var strength: Strength {
        switch abs(coefficient) {
        case ..<0.2: return .negligible
        case ..<0.4: return .weak
        case ..<0.6: return .moderate
        default:     return .strong
        }
    }

    /// Only surface associations backed by enough days and a non-negligible signal.
    var isMeaningful: Bool { sampleSize >= 8 && strength != .negligible }
}

enum HealthGlucoseCorrelator {
    /// Pearson r of paired `(x, y)` samples. `nil` if fewer than three points or
    /// either series has no variance (a flat series can't correlate).
    static func pearson(_ pairs: [(Double, Double)]) -> Double? {
        let n = Double(pairs.count)
        guard pairs.count >= 3 else { return nil }
        let sx = pairs.reduce(0) { $0 + $1.0 }
        let sy = pairs.reduce(0) { $0 + $1.1 }
        let sxx = pairs.reduce(0) { $0 + $1.0 * $1.0 }
        let syy = pairs.reduce(0) { $0 + $1.1 * $1.1 }
        let sxy = pairs.reduce(0) { $0 + $1.0 * $1.1 }
        let denom = ((n * sxx - sx * sx) * (n * syy - sy * sy)).squareRoot()
        guard denom > 0 else { return nil }
        let r = (n * sxy - sx * sy) / denom
        return max(-1, min(1, r))
    }

    /// Joins a daily health series and a daily-average-glucose series by calendar
    /// day, then correlates the matched pairs. Returns `nil` unless at least
    /// `minPairs` days line up.
    static func correlate(
        kind: HealthGlucoseCorrelation.Kind,
        health: [DailyMetric],
        glucose: [DailyMetric],
        calendar: Calendar = .current,
        minPairs: Int = 8
    ) -> HealthGlucoseCorrelation? {
        guard !health.isEmpty, !glucose.isEmpty else { return nil }
        var glucoseByDay: [Date: Double] = [:]
        for g in glucose { glucoseByDay[calendar.startOfDay(for: g.day)] = g.value }
        var pairs: [(Double, Double)] = []
        pairs.reserveCapacity(min(health.count, glucose.count))
        for h in health {
            if let gv = glucoseByDay[calendar.startOfDay(for: h.day)] {
                pairs.append((h.value, gv))
            }
        }
        guard pairs.count >= minPairs, let r = pearson(pairs) else { return nil }
        return HealthGlucoseCorrelation(kind: kind, coefficient: r, sampleSize: pairs.count)
    }
}
