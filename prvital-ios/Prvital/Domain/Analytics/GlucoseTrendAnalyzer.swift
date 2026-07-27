import Foundation

/// A computed glucose rate of change and the trend it implies. `mgdLPerMinute`
/// is the recency-weighted least-squares slope over the recent window; the
/// uncertainty figures let the forecast draw an honest, data-driven band
/// instead of a fixed-width guess.
struct GlucoseVelocity: Equatable, Sendable {
    let mgdLPerMinute: Double
    let trend: GlucoseTrend
    /// Residual scatter of the fit (mg/dL) — how noisy the recent stream is.
    var sigmaMgdL: Double = 5
    /// Standard error of the slope (mg/dL/min) — how firm the rate estimate is.
    var slopeSEPerMinute: Double = 0.1

    /// A linear projection `minutes` ahead, clamped to a non-negative value.
    func projectedMgdL(from currentMgdL: Double, minutes: Double) -> Double {
        max(0, currentMgdL + mgdLPerMinute * minutes)
    }
}

/// Derives a short-term glucose velocity and projection from recent readings.
///
/// The velocity is a *recency-weighted* least-squares slope over the recent
/// window: newer readings count more (weights halve every `halfLifeMinutes`),
/// so the rate tracks the stream's current direction instead of lagging behind
/// a turn the way a plain average does. One robust pass drops clear outliers
/// (compression lows, spikes) before the final fit, and the fit's residual
/// noise and slope standard error ride along for honest downstream bands.
/// Deterministic and unit-tested; drives only display (a projection is never a
/// substitute for a real reading).
enum GlucoseTrendAnalyzer {

    /// Recency-weighted least-squares slope (mg/dL per minute) over active
    /// readings within `window` of `now`. Returns `nil` unless there are at
    /// least three recent points with a real spread in time.
    static func velocity(
        _ readings: [GlucoseReading],
        now: Date,
        window: TimeInterval = 20 * 60,
        halfLifeMinutes: Double = 8
    ) -> GlucoseVelocity? {
        // x in minutes relative to `now` (<= 0), y in mg/dL.
        var points: [(x: Double, y: Double)] = readings
            .filter { $0.isActive && $0.timestamp <= now && now.timeIntervalSince($0.timestamp) <= window }
            .map { ($0.timestamp.timeIntervalSince(now) / 60, $0.valueMgdL) }
        guard points.count >= 3 else { return nil }

        func fit(_ pts: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double, sxx: Double)? {
            // Weight halves every halfLife minutes into the past (x <= 0).
            let ws = pts.map { exp($0.x * M_LN2 / halfLifeMinutes) }
            let sumW = ws.reduce(0, +)
            var meanX = 0.0, meanY = 0.0
            for (w, p) in zip(ws, pts) { meanX += w * p.x; meanY += w * p.y }
            meanX /= sumW; meanY /= sumW
            var sxx = 0.0, sxy = 0.0
            for (w, p) in zip(ws, pts) {
                sxx += w * (p.x - meanX) * (p.x - meanX)
                sxy += w * (p.x - meanX) * (p.y - meanY)
            }
            guard sxx > 1e-6 else { return nil } // readings share one instant
            return (sxy / sxx, meanY - (sxy / sxx) * meanX, sxx)
        }

        guard var line = fit(points) else { return nil }

        // One robust pass: a single compression low or spike shouldn't bend the
        // rate. The cutoff scales from the MEDIAN residual (an outlier inflates
        // an rms scale enough to hide itself behind it — the median stays put),
        // with a floor above ordinary sensor noise.
        let residuals = points.map { abs($0.y - (line.intercept + line.slope * $0.x)) }
        let medianResidual = residuals.sorted()[residuals.count / 2]
        let cutoff = max(8, 3 * medianResidual)
        let kept = zip(points, residuals).filter { $0.1 <= cutoff }.map(\.0)
        if kept.count >= 3, kept.count < points.count, let refit = fit(kept) {
            points = kept
            line = refit
        }

        let finalResiduals = points.map { $0.y - (line.intercept + line.slope * $0.x) }
        let sigma = (finalResiduals.reduce(0) { $0 + $1 * $1 } / Double(max(1, points.count - 2))).squareRoot()
        let slopeSE = sigma / line.sxx.squareRoot()
        return GlucoseVelocity(
            mgdLPerMinute: line.slope,
            trend: trend(forSlopePerMinute: line.slope),
            sigmaMgdL: sigma,
            slopeSEPerMinute: slopeSE)
    }

    /// The most *local* velocity available: tries progressively wider windows and
    /// returns the first (tightest) one that has enough points. The tight window
    /// gives the most precise current rate; the wider fallbacks keep the rate
    /// available through a missed reading instead of vanishing. Windows are in
    /// minutes; the default ladder is 20 → 30 → 45.
    static func bestVelocity(
        _ readings: [GlucoseReading], now: Date,
        windowsMinutes: [Double] = [20, 30, 45]
    ) -> GlucoseVelocity? {
        for minutes in windowsMinutes {
            if let v = velocity(readings, now: now, window: minutes * 60) { return v }
        }
        return nil
    }

    /// Maps a slope (mg/dL per minute) to the app's five trend levels using
    /// Dexcom's arrow convention: the flat arrow means "changing less than
    /// 1 mg/dL/min", so "stable" here is |slope| < 1 — the label can never
    /// contradict a displayed rate of ±1.2 again — and ±3 marks fast.
    static func trend(forSlopePerMinute slope: Double) -> GlucoseTrend {
        if slope >= 3 { return .risingFast }
        if slope >= 1 { return .rising }
        if slope <= -3 { return .fallingFast }
        if slope <= -1 { return .falling }
        return .stable
    }

    /// Minutes until glucose reaches `target` from `currentMgdL` at the given
    /// velocity — but only when it is genuinely heading toward it. Returns `nil`
    /// when the trend is too flat to project (|velocity| < 0.5 mg/dL/min) or is
    /// moving away from (or already past) the target.
    static func minutesToReach(_ target: Double, from currentMgdL: Double, velocityPerMinute: Double) -> Double? {
        guard abs(velocityPerMinute) >= 0.5 else { return nil }
        let minutes = (target - currentMgdL) / velocityPerMinute
        return minutes > 0 ? minutes : nil
    }

    /// Warns that a low or high is *imminent* — the current velocity projects
    /// crossing the target band within `horizonMinutes`, and only for a genuine
    /// trend (`|slope| >= minSlopePerMinute`). A shorter horizon and a real-slope
    /// floor keep the warning quiet until it's actually about to happen.
    static func imminentProjection(
        currentMgdL: Double,
        velocityPerMinute slope: Double,
        thresholds: GlucoseThresholds,
        horizonMinutes: Double = 30,
        minSlopePerMinute: Double = 1.0
    ) -> GlucoseProjection? {
        guard abs(slope) >= minSlopePerMinute else { return nil }
        if slope < 0, currentMgdL > thresholds.targetLower,
           let m = minutesToReach(thresholds.targetLower, from: currentMgdL, velocityPerMinute: slope),
           m <= horizonMinutes {
            return GlucoseProjection(kind: .low, minutes: Int(m.rounded()))
        }
        if slope > 0, currentMgdL < thresholds.targetUpper,
           let m = minutesToReach(thresholds.targetUpper, from: currentMgdL, velocityPerMinute: slope),
           m <= horizonMinutes {
            return GlucoseProjection(kind: .high, minutes: Int(m.rounded()))
        }
        return nil
    }
}

/// A short-term projection that a low or high is imminent.
struct GlucoseProjection: Equatable, Sendable {
    enum Kind: String, Sendable { case low, high }
    let kind: Kind
    let minutes: Int
}
