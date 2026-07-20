import Foundation

/// Summarises glucose during the overnight window (local 00:00–06:00), when
/// lows are most dangerous because they go unnoticed in sleep. Pure and
/// deterministic given a calendar: it filters the trace to overnight hours and
/// reuses the shared `StatisticsEngine`.
enum OvernightStability {
    /// Local hours [0, 6) treated as "overnight".
    static let hours = 0..<6

    static func analyze(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current
    ) -> PeriodStatistics? {
        let overnight = readings.filter {
            $0.isActive && hours.contains(calendar.component(.hour, from: $0.timestamp))
        }
        guard !overnight.isEmpty else { return nil }
        return StatisticsEngine.glucose(overnight, thresholds: thresholds)
    }
}
