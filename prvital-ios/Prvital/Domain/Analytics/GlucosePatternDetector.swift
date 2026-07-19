import Foundation

/// A part of the day, used to group readings when looking for recurring patterns.
enum DayPeriod: String, CaseIterable, Sendable {
    case overnight, morning, afternoon, evening

    /// Hours (24h) this period spans, as a half-open range.
    var hours: Range<Int> {
        switch self {
        case .overnight: return 0..<6
        case .morning: return 6..<12
        case .afternoon: return 12..<18
        case .evening: return 18..<24
        }
    }

    var label: String {
        switch self {
        case .overnight: return "Overnight"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        hours.contains(calendar.component(.hour, from: date))
    }
}

/// A plain-language pattern surfaced from the recent readings.
struct GlucoseInsight: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case frequentLow, frequentHigh }

    let period: DayPeriod
    let kind: Kind
    /// Fraction (0…1) of the period's readings that were low / high.
    let fraction: Double

    var id: String { "\(period.rawValue)-\(kind.rawValue)" }

    var symbol: String {
        kind == .frequentLow ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }
}

/// Detects recurring time-of-day glucose patterns. Pure and deterministic: it
/// buckets readings by `DayPeriod`, and — only when a period has enough data —
/// flags one that is low or high notably often. Lows are prioritised because
/// they are the more urgent pattern to act on.
enum GlucosePatternDetector {
    /// A period needs at least this many readings before a pattern is trusted.
    static let minReadings = 10
    /// Flag a period when this fraction of its readings are below range.
    static let lowFractionThreshold = 0.10
    /// Flag a period when this fraction of its readings are above range.
    static let highFractionThreshold = 0.25

    static func insights(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current
    ) -> [GlucoseInsight] {
        let active = readings.filter(\.isActive)
        var insights: [GlucoseInsight] = []

        for period in DayPeriod.allCases {
            let inPeriod = active.filter { period.contains($0.timestamp, calendar: calendar) }
            guard inPeriod.count >= minReadings else { continue }

            let stats = StatisticsEngine.glucose(inPeriod, thresholds: thresholds)
            if stats.timeBelowRange >= lowFractionThreshold {
                insights.append(GlucoseInsight(period: period, kind: .frequentLow, fraction: stats.timeBelowRange))
            } else if stats.timeAboveRange >= highFractionThreshold {
                insights.append(GlucoseInsight(period: period, kind: .frequentHigh, fraction: stats.timeAboveRange))
            }
        }

        // Lows first, then the strongest pattern.
        return insights.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .frequentLow }
            return lhs.fraction > rhs.fraction
        }
    }
}
