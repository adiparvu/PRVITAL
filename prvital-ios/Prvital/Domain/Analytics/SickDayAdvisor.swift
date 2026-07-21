import Foundation

/// The result of scanning recent glucose for a sustained run of highs.
struct SickDaySuggestion: Equatable, Sendable {
    var shouldSuggest: Bool
    var reason: Reason
    /// Mean glucose (mg/dL) over the sustained-high window, for the message.
    var averageMgdL: Double

    enum Reason: String, Sendable { case none, sustainedHighs }

    static let none = SickDaySuggestion(shouldSuggest: false, reason: .none, averageMgdL: 0)
}

/// Watches recent glucose for a *sustained* run of highs — the pattern that
/// warrants checking ketones and taking sick-day precautions — and suggests
/// (never forces) switching on sick-day mode. Pure and deterministic; the view
/// decides whether to surface it (e.g. only while sick-day mode is off).
enum SickDayAdvisor {
    /// The sick-day / ketone-check glucose threshold (mg/dL), matching the
    /// in-app education ("above 240 mg/dL / 13.3 mmol/L").
    static let highThresholdMgdL = 240.0
    /// How far back to look for a sustained run.
    static let windowHours = 3.0
    /// The run must actually span at least this long (not just a burst).
    static let minSpanHours = 2.0
    /// Minimum readings needed to call it sustained.
    static let minReadings = 3
    /// At least this fraction of the window's readings must be high.
    static let minHighFraction = 0.8

    static func evaluate(
        readings: [GlucoseReading],
        now: Date = Date()
    ) -> SickDaySuggestion {
        let windowStart = now.addingTimeInterval(-windowHours * 3600)
        let inWindow = readings
            .filter { $0.isActive && $0.timestamp >= windowStart && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
        guard inWindow.count >= minReadings, let earliest = inWindow.first else { return .none }

        // Must be a sustained stretch, not a cluster of near-simultaneous readings.
        guard now.timeIntervalSince(earliest.timestamp) >= minSpanHours * 3600 else { return .none }

        let highCount = inWindow.filter { $0.valueMgdL >= highThresholdMgdL }.count
        guard Double(highCount) / Double(inWindow.count) >= minHighFraction else { return .none }

        let mean = inWindow.map(\.valueMgdL).reduce(0, +) / Double(inWindow.count)
        return SickDaySuggestion(shouldSuggest: true, reason: .sustainedHighs, averageMgdL: mean)
    }
}
