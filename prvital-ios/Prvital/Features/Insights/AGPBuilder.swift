import Foundation
import SwiftData

/// Everything the AGP report shows, computed once per data change — plain
/// Sendable values, safe to hop off the builder actor.
struct AGPPayload: Sendable {
    var stats = PeriodStatistics()
    var buckets: [AGPBucket] = []
    var patterns: [GlucoseInsight] = []
    var comparison: StatComparison?
    var mealImpacts: [MealImpact] = []
    var mealImpactSummary: MealImpactSummary?
    var dawn: DawnPhenomenonResult?
    var dayType: DayTypeStats?
    var rebounds: [ReboundEvent] = []
    var activityImpact: ActivityImpactSummary?
    var readingCount = 0
}

/// Fetches and analyses the AGP window on a background ModelActor.
///
/// The report used to hold three live 400-day `@Query` sets and re-run every
/// analyzer as computed properties on each body render — with a long CGM
/// history that materialised ~100k rows and re-analysed them on the MAIN
/// thread, which is exactly the freeze doctor-visit mode was killed for
/// (0x8BADF00D watchdog). Now one bounded fetch covers the selected window
/// plus its comparison window, all ten analyses run here off-main, and the
/// view renders a finished value payload.
@ModelActor
actor AGPBuilder {

    func build(interval: InsightsInterval, thresholds: GlucoseThresholds) -> AGPPayload {
        let range = interval.dateRange()
        // The period-over-period comparison needs the window before this one
        // — except on Year, where fetching a second year of CGM just to draw
        // one delta row doubles the heaviest load in the app.
        let previousRange = interval == .year ? nil : interval.previousDateRange()
        let lower = min(range.lowerBound, previousRange?.lowerBound ?? range.lowerBound)
        let upper = range.upperBound

        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let rangeLower = range.lowerBound
        let carbs = (try? modelContext.fetch(FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= rangeLower && $0.timestamp <= upper }))) ?? []
        let activity = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.startTimestamp >= rangeLower && $0.startTimestamp <= upper }))) ?? []

        let window = readings.filter { range.contains($0.timestamp) }
        let previousWindow = previousRange.map { previous in
            readings.filter { previous.contains($0.timestamp) }
        } ?? []

        var payload = AGPPayload()
        payload.readingCount = window.count
        payload.stats = StatisticsEngine.glucose(window, thresholds: thresholds)
        payload.buckets = AGPAggregator.buckets(window, binMinutes: 60)
        payload.patterns = GlucosePatternDetector.insights(window, thresholds: thresholds)
        let previousStats = previousWindow.isEmpty
            ? nil : StatisticsEngine.glucose(previousWindow, thresholds: thresholds)
        payload.comparison = previousRange == nil
            ? nil
            : StatComparator.compare(current: payload.stats, previous: previousStats)
        payload.mealImpacts = MealImpactAnalyzer.analyze(meals: carbs, readings: window)
        payload.mealImpactSummary = MealImpactAnalyzer.summary(payload.mealImpacts)
        payload.dawn = DawnPhenomenonDetector.analyze(window)
        payload.dayType = WeekdayWeekendComparator.compare(window, thresholds: thresholds)
        payload.rebounds = ReboundDetector.detect(window, thresholds: thresholds)
        payload.activityImpact = ActivityImpactAnalyzer.summary(
            ActivityImpactAnalyzer.analyze(sessions: activity, readings: window))
        return payload
    }
}
