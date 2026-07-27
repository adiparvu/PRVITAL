import Foundation

/// A short-horizon glucose projection that's more faithful than a naive straight
/// line. Refinements over `current + rate × time`:
///
/// 1. **Damping** — glucose rarely holds a constant slope, so the current rate is
///    "spent" on an exponential curve (`v·τ·(1 − e^(−t/τ))`) that bends toward a
///    plateau instead of shooting off linearly.
/// 2. **Reading-age anchoring** — "in 30 minutes" means 30 minutes from *now*,
///    but the newest reading is typically a few minutes old; the projection
///    covers that gap too instead of silently pretending the reading is current.
/// 3. **Honest, data-driven range** — the plausible band combines the actual
///    uncertainty sources *in quadrature* (a straight sum overstates): the
///    sensor noise measured from the recent stream, how firm the rate estimate
///    itself is, and how much insulin/carbs are still in play — each scaled by
///    its real magnitude, not a fixed pad.
///
/// It is a projection, never a recommendation, and never a substitute for a real
/// reading. Pure and deterministic.
struct GlucoseForecast: Equatable, Sendable {
    let projectedMgdL: Double
    let lowMgdL: Double
    let highMgdL: Double
    let horizonMinutes: Int

    /// Damping time constant (minutes): larger τ = closer to linear.
    static let tau = 45.0

    /// - Parameters:
    ///   - minutesSinceReading: age of the newest reading. The displacement is
    ///     projected over `age + horizon` so the figure genuinely means
    ///     "horizon minutes from now". Capped at 15 — beyond that the stream is
    ///     stale and pretending otherwise would be false precision.
    ///   - sigmaMgdL: residual noise of the velocity fit (from
    ///     `GlucoseVelocity.sigmaMgdL`); defaults to a typical CGM scatter.
    ///   - slopeSEPerMinute: standard error of the fitted rate (from
    ///     `GlucoseVelocity.slopeSEPerMinute`).
    static func project(
        currentMgdL: Double,
        velocityMgdLPerMin velocity: Double,
        iob: Double = 0,
        cob: Double = 0,
        minutesSinceReading: Double = 0,
        sigmaMgdL: Double = 5,
        slopeSEPerMinute: Double = 0.1,
        horizonMinutes: Int = 30
    ) -> GlucoseForecast {
        let horizon = Double(max(1, horizonMinutes))
        let t = horizon + min(15, max(0, minutesSinceReading))
        let displacement = velocity * tau * (1 - exp(-t / tau))
        let point = min(400, max(40, currentMgdL + displacement))

        // Independent uncertainty sources, combined in quadrature and scaled by
        // the data itself — a tight, quiet night gives a tight band; a noisy
        // stream or a heavy meal bolus honestly widens it.
        let base = 8.0                                                  // sensor noise floor
        let rateTerm = min(25, max(0.05, slopeSEPerMinute) * t)         // rate itself uncertain
        let noiseTerm = max(3, sigmaMgdL) * (t / 5).squareRoot()        // scatter, per ~5-min step
        let iobTerm = iob >= 0.2 ? min(12, 2.4 * iob) : 0               // insulin still working
        let cobTerm = cob >= 5 ? min(12, 0.12 * cob) : 0                // carbs still absorbing
        let half = min(45, max(10, (
            base * base + rateTerm * rateTerm + noiseTerm * noiseTerm
                + iobTerm * iobTerm + cobTerm * cobTerm
        ).squareRoot()))

        return GlucoseForecast(
            projectedMgdL: point,
            lowMgdL: max(40, point - half),
            highMgdL: min(400, point + half),
            horizonMinutes: Int(horizon))
    }
}
