import Foundation
import SwiftData

/// Builds the ranked insights feed entirely OFF the main actor: a `@ModelActor`
/// owns its own background `ModelContext`, fetches the feed's bounded window
/// there, runs the analyzers there, and returns plain `Sendable` cards. The
/// main thread's only involvement is assigning the result — so entering the
/// Insights tab never pays a fetch or an analyzer pass on the render path.
///
/// (Before this, the feed's month of records was fetched through `@Query` during
/// the tab's body evaluation and analysed on the main actor — the second half of
/// the "switching to Insights lags" complaint, after the background-photo decode.)
@ModelActor
actor InsightsFeedBuilder {
    func build(range: ClosedRange<Date>, thresholds: GlucoseThresholds) -> [InsightCard] {
        let lower = range.lowerBound
        let upper = range.upperBound
        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let insulin = (try? modelContext.fetch(FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let carbs = (try? modelContext.fetch(FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let activity = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.startTimestamp >= lower && $0.startTimestamp <= upper },
            sortBy: [SortDescriptor(\.startTimestamp)]))) ?? []
        return InsightFeed.build(readings: readings, insulin: insulin, carbs: carbs,
                                 activity: activity, thresholds: thresholds)
    }
}
