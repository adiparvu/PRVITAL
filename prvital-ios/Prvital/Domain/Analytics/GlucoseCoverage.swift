import Foundation

/// Estimates CGM **data coverage** — the fraction of a period that has glucose
/// readings, assuming a nominal sensor cadence. This is the "% time active"
/// metric clinical guidance uses to judge whether summary statistics (notably
/// the GMI / estimated A1c) are trustworthy.
///
/// Pure and deterministic; it only needs the reading count and the window
/// length, so it is trivially testable.
enum GlucoseCoverage {
    /// Nominal minutes between CGM samples (Dexcom/Libre are ~5 minutes).
    static let nominalCadenceMinutes: Double = 5

    /// International consensus: a GMI is only reliable with ≥ 70% active time.
    static let reliableThreshold = 0.70

    /// Coverage fraction (0…1) for `readingCount` readings over `window`
    /// seconds, at the given cadence. Clamped to 1.
    static func coverage(readingCount: Int, window: TimeInterval, cadenceMinutes: Double = nominalCadenceMinutes) -> Double {
        guard window > 0, cadenceMinutes > 0, readingCount > 0 else { return 0 }
        let expected = window / (cadenceMinutes * 60)
        guard expected > 0 else { return 0 }
        return min(1, Double(readingCount) / expected)
    }

    /// Whether coverage is high enough for the GMI to be considered reliable.
    static func isReliable(_ coverage: Double) -> Bool {
        coverage >= reliableThreshold
    }
}
