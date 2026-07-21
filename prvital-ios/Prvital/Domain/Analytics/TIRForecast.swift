import Foundation

/// A projection of how today's Time-in-Range is likely to finish, blending what
/// has happened so far with the user's recent baseline.
struct TIRForecast: Equatable, Sendable {
    /// Time-in-Range so far today (0…1).
    var currentFraction: Double
    /// Projected end-of-day Time-in-Range (0…1).
    var projectedFraction: Double
    var confidence: Confidence
    var hasData: Bool

    enum Confidence: String, Sendable { case low, medium, high }

    static let none = TIRForecast(currentFraction: 0, projectedFraction: 0, confidence: .low, hasData: false)
}

/// Projects today's end-of-day Time-in-Range. Pure and deterministic.
///
/// The estimate is a weighted blend of today's actual TIR and the recent
/// baseline TIR, where the weight on *today* grows as the day elapses: early in
/// the morning the baseline dominates (little has happened yet); by evening
/// today's own readings carry almost all the weight. Confidence tracks how much
/// CGM data today already has.
enum TIRForecastEngine {
    static func forecast(
        today: [GlucoseReading],
        baseline: [GlucoseReading],
        thresholds: GlucoseThresholds,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TIRForecast {
        let todayActive = today.filter { $0.isActive && $0.timestamp <= now }
        guard !todayActive.isEmpty else { return .none }

        let todayStats = StatisticsEngine.glucose(todayActive, thresholds: thresholds)
        let todayTIR = todayStats.timeInRange

        // Baseline TIR over prior days; falls back to today's own TIR when there
        // isn't a history yet, so early days still produce a sensible number.
        let baselineActive = baseline.filter(\.isActive)
        let baselineTIR = baselineActive.isEmpty
            ? todayTIR
            : StatisticsEngine.glucose(baselineActive, thresholds: thresholds).timeInRange

        let startOfDay = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        let elapsedFraction = min(1, max(0, elapsed / 86_400))

        let projected = elapsedFraction * todayTIR + (1 - elapsedFraction) * baselineTIR

        // Confidence from today's coverage of the elapsed day.
        let coverage = GlucoseCoverage.coverage(readingCount: todayActive.count, window: max(elapsed, 60))
        let confidence: TIRForecast.Confidence
        if coverage >= 0.7 { confidence = .high }
        else if coverage >= 0.4 { confidence = .medium }
        else { confidence = .low }

        return TIRForecast(
            currentFraction: todayTIR,
            projectedFraction: min(1, max(0, projected)),
            confidence: confidence,
            hasData: true)
    }
}
