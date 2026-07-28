import Foundation

/// The clinical glycaemic-risk indices the big CGM reports (Clarity, Glooko,
/// LibreView) print alongside time-in-range. All are computed from the period's
/// readings alone, with the *fixed clinical cutoffs* (54 / 70 / 180 / 250 mg/dL)
/// — deliberately independent of the user's personal target range, so the
/// numbers are comparable to what a clinic sees.
struct GlycemicRisk: Equatable, Sendable {
    /// Low Blood Glucose Index (Kovatchev). < 1.1 minimal, 1.1–2.5 low,
    /// 2.5–5 moderate, > 5 high risk of hypoglycaemia.
    var lbgi: Double = 0
    /// High Blood Glucose Index (Kovatchev). < 4.5 low, 4.5–9 moderate,
    /// > 9 high risk of hyperglycaemia.
    var hbgi: Double = 0
    /// Mean Amplitude of Glycaemic Excursions, in mg/dL — the average size of
    /// the swings that exceed one standard deviation.
    var mage: Double = 0
    /// Glycemia Risk Index (Klonoff 2023), 0 (flat in range) … 100 (worst).
    /// GRI = 3.0 × hypo component + 1.6 × hyper component, capped at 100.
    var gri: Double = 0
    /// Hypo component: %time < 54 + 0.8 × %time 54–69 (percentage points).
    var hypoComponent: Double = 0
    /// Hyper component: %time > 250 + 0.5 × %time 181–250 (percentage points).
    var hyperComponent: Double = 0

    /// The five published GRI severity bands (quintiles), best → worst.
    enum Band: Int, CaseIterable, Sendable {
        case a, b, c, d, e
        init(gri: Double) {
            switch gri {
            case ..<20: self = .a
            case ..<40: self = .b
            case ..<60: self = .c
            case ..<80: self = .d
            default: self = .e
            }
        }
    }

    var band: Band { Band(gri: gri) }
}

enum GlycemicRiskEngine {

    /// Minimum readings for the indices to mean anything — a day of CGM or a
    /// couple of weeks of fingersticks.
    static let minimumReadings = 24

    /// Computes all indices over the period's active readings, or nil when the
    /// sample is too thin to be honest about.
    static func compute(_ readings: [GlucoseReading]) -> GlycemicRisk? {
        let ordered = readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= minimumReadings else { return nil }
        let values = ordered.map(\.valueMgdL)

        var risk = GlycemicRisk()

        // Kovatchev's symmetrised risk scale: f(BG) maps 112.5 mg/dL to 0,
        // lows to negative and highs to positive on a comparable scale;
        // r = 10·f² is the risk, split by sign into LBGI and HBGI.
        var lowSum = 0.0, highSum = 0.0
        for value in values {
            let clamped = max(20, min(600, value))
            let f = 1.509 * (pow(log(clamped), 1.084) - 5.381)
            let r = 10 * f * f
            if f < 0 { lowSum += r } else { highSum += r }
        }
        risk.lbgi = lowSum / Double(values.count)
        risk.hbgi = highSum / Double(values.count)

        // GRI, from time fractions at the fixed clinical cutoffs.
        let n = Double(values.count)
        let pVeryLow = Double(values.filter { $0 < 54 }.count) / n * 100
        let pLow = Double(values.filter { $0 >= 54 && $0 < 70 }.count) / n * 100
        let pVeryHigh = Double(values.filter { $0 > 250 }.count) / n * 100
        let pHigh = Double(values.filter { $0 > 180 && $0 <= 250 }.count) / n * 100
        risk.hypoComponent = pVeryLow + 0.8 * pLow
        risk.hyperComponent = pVeryHigh + 0.5 * pHigh
        risk.gri = min(100, 3.0 * risk.hypoComponent + 1.6 * risk.hyperComponent)

        risk.mage = Self.mage(values)
        return risk
    }

    /// Classic MAGE: find the series' turning points, measure the swing between
    /// each consecutive peak/nadir pair, and average only the swings larger than
    /// one standard deviation of the whole period.
    static func mage(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sd = (values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)).squareRoot()
        guard sd > 0 else { return 0 }

        // Turning points: keep the first and last value plus every local
        // extremum where the direction of travel flips.
        var extrema: [Double] = [values[0]]
        var direction = 0   // -1 falling, +1 rising, 0 unknown
        for index in 1..<values.count {
            let delta = values[index] - values[index - 1]
            guard delta != 0 else { continue }
            let newDirection = delta > 0 ? 1 : -1
            if direction != 0 && newDirection != direction {
                extrema.append(values[index - 1])
            }
            direction = newDirection
        }
        extrema.append(values[values.count - 1])

        var amplitudes: [Double] = []
        for index in 1..<extrema.count {
            let amplitude = abs(extrema[index] - extrema[index - 1])
            if amplitude > sd { amplitudes.append(amplitude) }
        }
        guard !amplitudes.isEmpty else { return 0 }
        return amplitudes.reduce(0, +) / Double(amplitudes.count)
    }
}
