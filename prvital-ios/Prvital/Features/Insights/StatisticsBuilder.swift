import Foundation
import SwiftData

/// Everything the Statistics pane shows for one window — plain Sendable values,
/// safe to hand back from the builder actor.
struct StatisticsPayload: Sendable {
    var stats = PeriodStatistics()
    var activityMinutes = 0
    var hasAnyData = false
    var hypoRecovery: HypoRecoveryStats?
    var gmiTrend: [GMIPoint] = []
    var labResultsInRange: [LabPoint] = []
    var latestReconciliation: A1cReconciliation?
    var a1cProjection: A1cProjectionResult?
    var sensorAccuracy: SensorAccuracyResult?
    var tirTrend: [TIRPoint] = []
    var dataGaps: GapStats?
    var insulinSummary: InsulinSummary?
    var dailyDays: [DayTIR] = []
    var overnightStats: PeriodStatistics?
    var carbsByMeal: [MealTypeCarbs] = []
    var periodTIRs: [PeriodTIR] = []
    var previousPeriodTIR: Double?
    /// The whole previous-window statistics, for the "what changed" narrative.
    var previousStats: PeriodStatistics?
    var risk: GlycemicRisk?
    var tagImpacts: [TagImpact] = []
    var hypoTreatments: HypoTreatmentStats?
}

/// Fetches and analyses the Statistics window on a background ModelActor.
///
/// The pane used to hold six live `@Query` sets windowed to the interval, so
/// entering Analyze materialised the whole window on the MAIN thread during
/// view construction — a year is ~100k CGM rows — and every sync re-did it
/// while the tab stayed alive. That was the delay on tapping the tab. Now one
/// bounded fetch and all fifteen analyses run here, off-main, and the view
/// renders a finished value payload (same pattern as ChartsBuilder/AGPBuilder).
@ModelActor
actor StatisticsBuilder {

    func build(
        interval: InsightsInterval,
        healthExercise: [DailyMetric],
        thresholds: GlucoseThresholds,
        periodTargets: PeriodTIRTargets,
        globalTargetPercent: Double
    ) -> StatisticsPayload {
        let range = interval.dateRange()
        let lower = range.lowerBound
        let upper = range.upperBound

        // Every reading in the window, superseded ones included: sensor
        // accuracy compares reference ↔ sensor pairs and needs both.
        let windowGlucose = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let fInsulin = (try? modelContext.fetch(FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fCarbs = (try? modelContext.fetch(FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fActivity = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.startTimestamp >= lower && $0.startTimestamp <= upper }))) ?? []
        let fObservations = (try? modelContext.fetch(FetchDescriptor<ObservationEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let labResults = (try? modelContext.fetch(FetchDescriptor<LabResult>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []

        let active = windowGlucose.filter(\.isActive)

        var payload = StatisticsPayload()
        payload.labResultsInRange = labResults
            .filter { range.contains($0.timestamp) }
            .map { LabPoint(id: $0.id, timestamp: $0.timestamp, value: $0.value) }

        let base = StatisticsEngine.glucose(active, thresholds: thresholds)
        payload.stats = StatisticsEngine.enrich(
            base, insulin: fInsulin, carbs: fCarbs, activity: fActivity)
        payload.activityMinutes = StatisticsDerived.mergedActivityMinutes(
            logged: fActivity, health: healthExercise, range: range)
        payload.hasAnyData = payload.stats.hasGlucose || !fInsulin.isEmpty || !fCarbs.isEmpty
            || !fActivity.isEmpty || payload.activityMinutes > 0

        payload.gmiTrend = GMITrend.weekly(active)
        // Reconciliation compares a lab result with the ~90 days of CGM it
        // reflects — wider than the selected window, and only when a lab exists.
        if let latestLab = labResults.first {
            // Both bounds must be plain local values: `#Predicate` cannot
            // capture a property read off a SwiftData model.
            let labDate = latestLab.timestamp
            let reconLower = Calendar.current.date(byAdding: .day, value: -100, to: labDate)
                ?? labDate.addingTimeInterval(-100 * 86_400)
            let reconReadings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
                predicate: #Predicate {
                    $0.isActive && $0.timestamp >= reconLower && $0.timestamp <= labDate
                },
                sortBy: [SortDescriptor(\.timestamp)]))) ?? []
            payload.latestReconciliation = A1cReconciler.reconcile(
                lab: latestLab, readings: reconReadings, thresholds: thresholds)
        }
        payload.a1cProjection = {
            guard let p = A1cProjection.project(payload.gmiTrend), p.confidence == .ok else { return nil }
            return p
        }()
        payload.sensorAccuracy = SensorAccuracyAnalyzer.analyze(windowGlucose)
        payload.tirTrend = TIRTrend.weekly(active, thresholds: thresholds)
        payload.dataGaps = DataGapDetector.analyze(active)
        payload.insulinSummary = InsulinAnalyzer.summary(fInsulin)
        payload.dailyDays = DailyBreakdown.perDay(active, thresholds: thresholds)
        payload.overnightStats = OvernightStability.analyze(active, thresholds: thresholds)
        payload.carbsByMeal = CarbDistribution.byMealType(fCarbs)
        payload.hypoRecovery = HypoRecoveryAnalyzer.analyze(active, thresholds: thresholds)
        payload.periodTIRs = PeriodTIRAnalyzer.breakdown(
            active, thresholds: thresholds,
            targets: periodTargets, globalTargetPercent: globalTargetPercent)
        payload.risk = GlycemicRiskEngine.compute(active)
        payload.tagImpacts = TagImpactAnalyzer.analyze(
            readings: active, carbs: fCarbs, observations: fObservations, thresholds: thresholds)
        payload.hypoTreatments = HypoTreatmentAnalyzer.analyze(readings: active, carbs: fCarbs)

        // The equally long window immediately before this one, for the
        // "±X% vs the previous …" line. Skipped on Year, where a second year of
        // CGM just for one row is the heaviest fetch in the app.
        if interval != .year {
            let duration = upper.timeIntervalSince(lower)
            let prevLower = lower.addingTimeInterval(-duration)
            let previous = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
                predicate: #Predicate {
                    $0.isActive && $0.timestamp >= prevLower && $0.timestamp < lower
                }))) ?? []
            let prevStats = StatisticsEngine.glucose(previous, thresholds: thresholds)
            payload.previousPeriodTIR = prevStats.hasGlucose ? prevStats.timeInRange : nil
            payload.previousStats = prevStats.hasGlucose ? prevStats : nil
        }

        return payload
    }
}
