import Foundation

/// How urgent an insight is, driving both its rank and its tint. Ordered so the
/// clinically most important findings (lows) sort to the top of the feed.
enum InsightSeverity: Int, Comparable, Sendable {
    case informational = 0
    case low = 1
    case moderate = 2
    case high = 3
    case critical = 4

    static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A UI-agnostic colour intent for a card. The view layer maps these to `Theme`
/// glucose-zone colours; keeping it a plain enum lets `InsightFeed` stay free of
/// SwiftUI so the whole aggregation is unit-testable.
enum InsightTint: String, Sendable {
    case critical   // red — lows
    case warning    // orange — rebound / slow recovery / hypo risk
    case high       // yellow — highs / meal spikes / dawn
    case positive   // green — a helpful pattern
    case neutral    // accent
}

/// A single, human-readable, tappable finding surfaced to the user — the unit the
/// Insights feed renders. Pure value type: `Sendable` and `Equatable`, no UI.
struct InsightCard: Identifiable, Equatable, Sendable {
    let id: String
    /// Short headline, e.g. "Often low overnight".
    let title: String
    /// One-line supporting detail, e.g. "Breakfast spikes +80 mg/dL".
    let detail: String
    /// SF Symbol name for the card's icon.
    let systemImage: String
    let severity: InsightSeverity
    let tint: InsightTint
    /// Recency of the underlying signal, used only to break ranking ties. Nil for
    /// aggregate patterns that aren't anchored to a single moment.
    let date: Date?
    /// Fine-grained rank *within* a severity tier — the normalised (0…1) magnitude
    /// of the finding, so the strongest pattern in a tier leads.
    let priority: Double
}

/// Turns the app's existing analyzers into a ranked, capped list of `InsightCard`s.
///
/// Pure and deterministic: it takes plain record arrays plus the user's
/// thresholds, runs each existing analyzer, converts every meaningful finding
/// into a card, and ranks them by clinical importance (lows → low-recovery →
/// variability/highs → meal spikes → activity), then recency. No SwiftUI, no
/// SwiftData queries — the view just renders whatever this returns.
enum InsightFeed {
    /// Most cards shown in the feed.
    static let maxCards = 5

    // Surfacing thresholds — kept explicit so the ranking is easy to reason about
    // and to test. A finding must clear its bar before it becomes a card.
    static let reboundMinEvents = 2
    static let hypoRecoveryMinEpisodes = 2
    static let hypoRecoverySlowMinutes: Double = 20
    static let mealSpikeThresholdMgdL: Double = 50
    static let mealSpikeMinMeals = 2
    static let maxMealCards = 2
    static let activityDropThresholdMgdL: Double = 15
    static let activityLargeDropMgdL: Double = 45
    static let activityMinSessions = 2

    /// Runs every analyzer over the supplied records and returns the top cards.
    /// `insulin` is accepted for a complete call site but no existing analyzer
    /// consumes it directly, so it is currently unused.
    static func build(
        readings: [GlucoseReading],
        insulin: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        activity: [ActivityEntry] = [],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current
    ) -> [InsightCard] {
        _ = insulin

        var cards: [InsightCard] = []
        cards += glucosePatternCards(readings, thresholds: thresholds, calendar: calendar)
        cards += reboundCards(readings, thresholds: thresholds)
        cards += hypoRecoveryCards(readings, thresholds: thresholds)
        cards += dawnCards(readings, calendar: calendar)
        cards += mealCards(readings: readings, carbs: carbs)
        cards += activityCards(readings: readings, activity: activity)
        return rank(cards)
    }

    /// Sorts by severity, then within-tier priority, then recency, and caps the
    /// result. Deterministic: ties fall back to the (stable) card id.
    static func rank(_ cards: [InsightCard]) -> [InsightCard] {
        let sorted = cards.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            switch (lhs.date, rhs.date) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true          // dated signals lead undated ones
            case (nil, _?): return false
            default: return lhs.id < rhs.id
            }
        }
        return Array(sorted.prefix(maxCards))
    }

    // MARK: - Time-of-day patterns (GlucosePatternDetector)

    private static func glucosePatternCards(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds,
        calendar: Calendar
    ) -> [InsightCard] {
        GlucosePatternDetector.insights(readings, thresholds: thresholds, calendar: calendar).map { insight in
            let pct = percent(insight.fraction)
            let period = insight.period.label.lowercased()
            switch insight.kind {
            case .frequentLow:
                return InsightCard(
                    id: "pattern-\(insight.id)",
                    title: "Often low \(phrase(insight.period))",
                    detail: "\(pct)% of \(period) readings are below range",
                    systemImage: "arrow.down.circle.fill",
                    severity: .critical,
                    tint: .critical,
                    date: nil,
                    priority: insight.fraction
                )
            case .frequentHigh:
                return InsightCard(
                    id: "pattern-\(insight.id)",
                    title: "Often high \(phrase(insight.period))",
                    detail: "\(pct)% of \(period) readings are above range",
                    systemImage: "arrow.up.circle.fill",
                    severity: .moderate,
                    tint: .high,
                    date: nil,
                    priority: insight.fraction
                )
            }
        }
    }

    // MARK: - Rebound highs after lows (ReboundDetector)

    private static func reboundCards(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds
    ) -> [InsightCard] {
        let events = ReboundDetector.detect(readings, thresholds: thresholds)
        guard events.count >= reboundMinEvents else { return [] }
        return [InsightCard(
            id: "rebound",
            title: "Rebound highs after lows",
            detail: "Glucose spiked high after a low \(events.count) times — watch for over-treating lows",
            systemImage: "arrow.up.arrow.down",
            severity: .high,
            tint: .warning,
            date: events.map(\.highTime).max(),
            priority: min(Double(events.count) / 6, 1)
        )]
    }

    // MARK: - Slow hypo recovery (HypoRecoveryAnalyzer)

    private static func hypoRecoveryCards(
        _ readings: [GlucoseReading],
        thresholds: GlucoseThresholds
    ) -> [InsightCard] {
        guard let stats = HypoRecoveryAnalyzer.analyze(readings, thresholds: thresholds),
              stats.episodeCount >= hypoRecoveryMinEpisodes,
              stats.averageMinutes >= hypoRecoverySlowMinutes else { return [] }
        let mins = Int(stats.averageMinutes.rounded())
        return [InsightCard(
            id: "hypo-recovery",
            title: "Lows are slow to recover",
            detail: "Lows take about \(mins) min to return to range over \(stats.episodeCount) episodes",
            systemImage: "clock.arrow.circlepath",
            severity: .high,
            tint: .warning,
            date: nil,
            priority: min(stats.averageMinutes / 60, 1)
        )]
    }

    // MARK: - Dawn phenomenon (DawnPhenomenonDetector)

    private static func dawnCards(_ readings: [GlucoseReading], calendar: Calendar) -> [InsightCard] {
        guard let dawn = DawnPhenomenonDetector.analyze(readings, calendar: calendar), dawn.isPresent else { return [] }
        let rise = Int(dawn.medianRiseMgdL.rounded())
        return [InsightCard(
            id: "dawn",
            title: "Dawn phenomenon",
            detail: "Glucose climbs about +\(rise) mg/dL before breakfast across \(dawn.dayCount) days",
            systemImage: "sunrise.fill",
            severity: .moderate,
            tint: .high,
            date: nil,
            priority: min(dawn.medianRiseMgdL / 60, 1)
        )]
    }

    // MARK: - Meal spikes (MealImpactAnalyzer)

    private static func mealCards(readings: [GlucoseReading], carbs: [CarbEntry]) -> [InsightCard] {
        let impacts = MealImpactAnalyzer.analyze(meals: carbs, readings: readings)
        guard !impacts.isEmpty else { return [] }

        // Group the per-meal excursions the analyzer produced by meal type, then
        // surface the types whose average rise clears the spike threshold.
        var byType: [MealType: [MealImpact]] = [:]
        for impact in impacts { byType[impact.mealType, default: []].append(impact) }

        let cards: [InsightCard] = byType.compactMap { type, group in
            guard group.count >= mealSpikeMinMeals else { return nil }
            let avgRise = group.reduce(0) { $0 + $1.deltaMgdL } / Double(group.count)
            guard avgRise >= mealSpikeThresholdMgdL else { return nil }
            let avgMinutes = Int((group.reduce(0) { $0 + Double($1.minutesToPeak) } / Double(group.count)).rounded())
            let rise = Int(avgRise.rounded())
            return InsightCard(
                id: "meal-\(type.rawValue)",
                title: "\(type.label) spikes +\(rise) mg/dL",
                detail: "Peaks about \(avgMinutes) min after eating, over \(group.count) meals",
                systemImage: type.symbol,
                severity: .low,
                tint: .high,
                date: group.map(\.mealTime).max(),
                priority: min(avgRise / 120, 1)
            )
        }
        // Keep only the strongest couple so meals don't crowd out other findings.
        return Array(cards.sorted { $0.priority > $1.priority }.prefix(maxMealCards))
    }

    // MARK: - Activity impact (ActivityImpactAnalyzer)

    private static func activityCards(readings: [GlucoseReading], activity: [ActivityEntry]) -> [InsightCard] {
        let impacts = ActivityImpactAnalyzer.analyze(sessions: activity, readings: readings)
        guard impacts.count >= activityMinSessions,
              let summary = ActivityImpactAnalyzer.summary(impacts),
              summary.averageChangeMgdL <= -activityDropThresholdMgdL else { return [] }
        let drop = Int(abs(summary.averageChangeMgdL).rounded())
        let large = summary.averageChangeMgdL <= -activityLargeDropMgdL
        return [InsightCard(
            id: "activity",
            title: "Activity lowers your glucose",
            detail: large
                ? "Glucose drops about \(drop) mg/dL after activity — watch for lows"
                : "Glucose drops about \(drop) mg/dL after activity, across \(summary.count) sessions",
            systemImage: "figure.walk.motion",
            severity: .informational,
            tint: large ? .warning : .positive,
            date: impacts.map(\.start).max(),
            priority: min(Double(drop) / 60, 1)
        )]
    }

    // MARK: - Formatting helpers

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    private static func phrase(_ period: DayPeriod) -> String {
        switch period {
        case .overnight: return "overnight"
        case .morning: return "in the morning"
        case .afternoon: return "in the afternoon"
        case .evening: return "in the evening"
        }
    }
}
