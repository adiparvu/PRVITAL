import Foundation

/// The phase a sensor session is in right now.
enum SensorPhase: String, Sendable {
    case warmup
    case active
    case expiringSoon
    case expired
}

/// A display-ready summary of where a sensor session stands.
struct SensorStatus: Sendable, Equatable {
    let phase: SensorPhase
    /// Seconds until the next milestone: end of warm-up (warmup) or expiry
    /// (active / expiringSoon). Zero once expired.
    let timeRemaining: TimeInterval
    /// Fraction of the total wear time elapsed, clamped 0…1.
    let progress: Double
}

/// Pure evaluation of a sensor session against the clock.
enum SensorSessionEvaluator {

    /// Evaluates a session:
    /// - `.warmup` until warm-up completes,
    /// - `.expiringSoon` within `expiringWithin` of the end,
    /// - `.expired` at/after the end,
    /// - `.active` otherwise.
    static func status(
        start: Date,
        kind: SensorKind,
        now: Date,
        expiringWithin: TimeInterval = 12 * 3_600
    ) -> SensorStatus {
        let elapsed = now.timeIntervalSince(start)
        let lifetime = kind.lifetime
        let progress = min(max(elapsed / lifetime, 0), 1)
        let remainingToExpiry = lifetime - elapsed

        if elapsed < 0 {
            // Session marked as starting in the future — treat as warming up.
            return SensorStatus(phase: .warmup, timeRemaining: kind.warmup, progress: 0)
        }
        if remainingToExpiry <= 0 {
            return SensorStatus(phase: .expired, timeRemaining: 0, progress: 1)
        }
        if elapsed < kind.warmup {
            return SensorStatus(phase: .warmup, timeRemaining: kind.warmup - elapsed, progress: progress)
        }
        if remainingToExpiry <= expiringWithin {
            return SensorStatus(phase: .expiringSoon, timeRemaining: remainingToExpiry, progress: progress)
        }
        return SensorStatus(phase: .active, timeRemaining: remainingToExpiry, progress: progress)
    }
}
