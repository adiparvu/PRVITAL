import Foundation

/// Where the estimated-A1c trend lands 90 days out, with a rough confidence
/// grade for whether the trajectory is worth showing at all.
struct A1cProjectionResult {
    enum Confidence {
        /// Too few weekly points, or the weeks scatter widely around the fitted
        /// line — the trajectory is not trustworthy enough to display.
        case low
        case ok
    }

    /// Estimated A1c (%) 90 days after the last trend point, clamped to the
    /// physiologically plausible 4.0–14.0 % band.
    let projectedA1cPercent: Double
    /// Fitted trend slope, in A1c percentage points per week.
    let slopePerWeek: Double
    let confidence: Confidence
}

/// Projects the weekly estimated-A1c (GMI) series forward with an ordinary
/// least-squares line.
///
/// Pure and deterministic: the last up-to-8 weekly points (sorted by week
/// start) are fitted with x measured in weeks since the earliest fitted point —
/// real calendar gaps between weeks count — and the line is evaluated 90 days
/// past the last point.
///
/// The confidence heuristic is deliberately simple: `.low` when fewer than 4
/// points were fitted, or when the root-mean-square residual of the fit exceeds
/// 0.25 A1c percentage points (the weekly values disagree with a straight
/// line); `.ok` otherwise.
enum A1cProjection {
    static let maxPointsUsed = 8
    static let minimumPoints = 3
    static let projectionDays: Double = 90
    static let clampRange: ClosedRange<Double> = 4.0...14.0
    static let confidentMinimumPoints = 4
    /// Root-mean-square residual (in A1c percentage points) above which the
    /// fit is graded `.low`.
    static let residualRMSELimit = 0.25

    static func project(_ points: [GMIPoint]) -> A1cProjectionResult? {
        let ordered = Array(points.sorted { $0.weekStart < $1.weekStart }.suffix(maxPointsUsed))
        guard ordered.count >= minimumPoints, let first = ordered.first else { return nil }

        let secondsPerWeek = 7.0 * 86_400
        let xs = ordered.map { $0.weekStart.timeIntervalSince(first.weekStart) / secondsPerWeek }
        let ys = ordered.map(\.gmi)
        let n = Double(ordered.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var sxx = 0.0
        var sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        // All points in the same week — no time axis to fit against.
        guard sxx > 0, let lastX = xs.last else { return nil }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        let projectedX = lastX + projectionDays / 7
        let raw = intercept + slope * projectedX
        let projected = min(max(raw, clampRange.lowerBound), clampRange.upperBound)

        let meanSquareResidual = zip(xs, ys).reduce(0.0) { sum, pair in
            let residual = pair.1 - (intercept + slope * pair.0)
            return sum + residual * residual
        } / n
        let confidence: A1cProjectionResult.Confidence =
            (ordered.count < confidentMinimumPoints || meanSquareResidual.squareRoot() > residualRMSELimit)
                ? .low
                : .ok

        return A1cProjectionResult(
            projectedA1cPercent: projected,
            slopePerWeek: slope,
            confidence: confidence
        )
    }
}
