import Foundation

/// A short-horizon glucose projection that's more faithful than a naive straight
/// line. Two refinements over `current + rate × time`:
///
/// 1. **Damping** — glucose rarely holds a constant slope, so the current rate is
///    "spent" on an exponential curve (`v·τ·(1 − e^(−t/τ))`) that bends toward a
///    plateau instead of shooting off linearly.
/// 2. **Honest range** — rather than pretend a single future value is certain, it
///    returns a plausible band that widens with how fast/far we project and with
///    how much insulin or carbs are still on board (more in play → less certain).
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

    static func project(
        currentMgdL: Double,
        velocityMgdLPerMin velocity: Double,
        iob: Double = 0,
        cob: Double = 0,
        horizonMinutes: Int = 30
    ) -> GlucoseForecast {
        let t = Double(max(1, horizonMinutes))
        let displacement = velocity * tau * (1 - exp(-t / tau))
        let point = max(40, currentMgdL + displacement)

        // Honest uncertainty half-width.
        let base = 10.0                          // sensor noise floor
        let motion = 0.15 * abs(velocity) * t    // faster/further → less certain
        let onBoard = (iob >= 0.2 ? 12.0 : 0) + (cob >= 5 ? 12.0 : 0)
        let half = base + motion + onBoard

        return GlucoseForecast(
            projectedMgdL: point,
            lowMgdL: max(40, point - half),
            highMgdL: point + half,
            horizonMinutes: Int(t))
    }
}
