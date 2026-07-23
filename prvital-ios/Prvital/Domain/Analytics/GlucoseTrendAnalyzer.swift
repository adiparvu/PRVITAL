import Foundation

/// A computed glucose rate of change and the trend it implies. `mgdLPerMinute`
/// is the least-squares slope over the recent window; the projection lets the
/// dashboard show where glucose is heading.
struct GlucoseVelocity: Equatable, Sendable {
    let mgdLPerMinute: Double
    let trend: GlucoseTrend

    /// A linear projection `minutes` ahead, clamped to a non-negative value.
    func projectedMgdL(from currentMgdL: Double, minutes: Double) -> Double {
        max(0, currentMgdL + mgdLPerMinute * minutes)
    }
}

/// Derives a short-term glucose velocity and projection from recent readings.
///
/// The velocity is the ordinary least-squares slope of value over time across
/// the recent window — more robust to a single noisy point than a two-point
/// delta. It's a deterministic function of the readings, so it is unit-tested
/// and drives only display (a projection is never a substitute for a real
/// reading).
enum GlucoseTrendAnalyzer {

    /// Least-squares slope (mg/dL per minute) over active readings within
    /// `window` of `now`. Returns `nil` unless there are at least three recent
    /// points with a real spread in time.
    static func velocity(
        _ readings: [GlucoseReading],
        now: Date,
        window: TimeInterval = 20 * 60
    ) -> GlucoseVelocity? {
        let recent = readings.filter {
            $0.isActive && $0.timestamp <= now && now.timeIntervalSince($0.timestamp) <= window
        }
        guard recent.count >= 3 else { return nil }

        // x in minutes relative to `now` (<= 0), y in mg/dL.
        let xs = recent.map { $0.timestamp.timeIntervalSince(now) / 60 }
        let ys = recent.map(\.valueMgdL)
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for i in xs.indices {
            let dx = xs[i] - meanX
            numerator += dx * (ys[i] - meanY)
            denominator += dx * dx
        }
        guard denominator > 1e-6 else { return nil } // readings share one instant

        let slope = numerator / denominator
        return GlucoseVelocity(mgdLPerMinute: slope, trend: trend(forSlopePerMinute: slope))
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

    /// Maps a slope (mg/dL per minute) to the app's five trend levels using the
    /// conventional CGM cutoffs (±1.5 and ±3 mg/dL/min).
    static func trend(forSlopePerMinute slope: Double) -> GlucoseTrend {
        if slope >= 3 { return .risingFast }
        if slope >= 1.5 { return .rising }
        if slope <= -3 { return .fallingFast }
        if slope <= -1.5 { return .falling }
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
