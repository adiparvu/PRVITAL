import SwiftUI
import SwiftData
import Charts

/// Identifiable wrapper so a tapped best/toughest day can drive `.sheet(item:)`.
private struct StatDayRef: Identifiable {
    let day: Date
    var id: Date { day }
}

/// The numeric pane of Insights: a computed `PeriodStatistics` for the selected
/// interval, rendered as a grid of `StatTile`s plus a Time-in-Range stacked bar.
/// Glucose figures are always formatted through `GlucoseFormatting` in the user's
/// unit; percentages use the `value * 100` rounding rule.
/// A thin wrapper that re-creates its windowed content whenever the interval
/// changes, so each interval fetches only its own window (Day ≈ 288 readings, not
/// the whole ~100k-row history). Materialising a year of readings on every
/// appearance was what still blocked the main thread on navigation into the tab,
/// even after the computation itself was moved off it.
struct StatisticsView: View {
    @Binding var interval: InsightsInterval
    /// The Insights feed, rendered as the first scrolling element so it moves
    /// with the page as one whole (device feedback).
    var pinnedHeader: AnyView? = nil

    var body: some View {
        StatisticsContent(interval: interval, pinnedHeader: pinnedHeader).id(interval)
    }
}

struct StatisticsContent: View {
    @Environment(AppEnvironment.self) private var env

    let interval: InsightsInterval
    var pinnedHeader: AnyView? = nil

    @Environment(\.modelContext) private var modelContext

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]
    @Query(sort: \LabResult.timestamp, order: .reverse) private var labResults: [LabResult]

    init(interval: InsightsInterval, pinnedHeader: AnyView? = nil) {
        self.interval = interval
        self.pinnedHeader = pinnedHeader
        // Window every query to the SELECTED interval, so Day loads a day and only
        // Year loads a year — instead of a fixed 400-day fetch regardless of view.
        let cutoff = interval.dateRange().lowerBound
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
        _observations = Query(filter: #Predicate<ObservationEntry> { $0.timestamp >= cutoff },
                              sort: \.timestamp, order: .reverse)
    }
    @State private var showingLogLab = false
    /// The day whose detail sheet is open (tapping the best/toughest day).
    @State private var selectedDay: StatDayRef?

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    // MARK: Derived (computed once per data change in `.task`, cached below)
    //
    // Previously each of these was a computed property that re-filtered up to a
    // year of CGM readings (~100k) and re-ran its analyzer on EVERY body render —
    // and several were read 3–4 times per render (e.g. `stats`, via `hasAnyData`,
    // `timeInRangeBar` and `statsGrid`). That made the Statistics pane load slowly
    // and stutter. Now the whole batch is computed once, off the first-paint path,
    // into `derived`; these thin accessors just read the cached results, so the
    // body and every card builder stay unchanged.

    @State private var derived = StatisticsDerived()
    // Apple Health's daily exercise minutes for the window, merged into the
    // "Active time" figure so it matches the Move ring and the Activity chart.
    @State private var healthExercise: [DailyMetric] = []

    private var stats: PeriodStatistics { derived.stats }
    private var activityMinutes: Int { derived.activityMinutes }
    private var hasAnyData: Bool { derived.hasAnyData }
    private var hypoRecovery: HypoRecoveryStats? { derived.hypoRecovery }
    private var gmiTrend: [GMIPoint] { derived.gmiTrend }
    private var labResultsInRange: [LabResult] { derived.labResultsInRange }
    private var latestReconciliation: A1cReconciliation? { derived.latestReconciliation }
    private var a1cProjection: A1cProjectionResult? { derived.a1cProjection }
    private var sensorAccuracy: SensorAccuracyResult? { derived.sensorAccuracy }
    private var tirTrend: [TIRPoint] { derived.tirTrend }
    private var dataGaps: GapStats? { derived.dataGaps }
    private var insulinSummary: InsulinSummary? { derived.insulinSummary }
    private var dailyDays: [DayTIR] { derived.dailyDays }
    private var overnightStats: PeriodStatistics? { derived.overnightStats }
    private var carbsByMeal: [MealTypeCarbs] { derived.carbsByMeal }
    private var periodTIRs: [PeriodTIR] { derived.periodTIRs }

    /// Cheap, Equatable fingerprint — reruns the rebuild only when data is
    /// added/removed or the interval switches, not on ordinary re-renders.
    private var signature: StatisticsSignature {
        StatisticsSignature(
            interval: interval,
            glucose: glucose.count, insulin: insulin.count, carbs: carbs.count,
            activity: activity.count, observations: observations.count, labs: labResults.count,
            newest: glucose.first?.timestamp,
            thresholds: thresholds,
            periodTargets: env.preferences.periodTIRTargets,
            globalTargetPercent: env.preferences.glucoseGoals.targetTIRPercent,
            healthExerciseDays: healthExercise.count,
            healthExerciseTotal: Int(healthExercise.reduce(0.0) { $0 + $1.value }.rounded()))
    }

    /// A ~95-day glucose window fetched on demand for the A1c reconciliation (it
    /// needs the span a lab reflects, wider than the selected interval). Called
    /// only when a lab result exists, so the common case never pays for it.
    static func fetchReconReadings(_ env: AppEnvironment) -> [GlucoseReading] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -95, to: Date())
            ?? Date().addingTimeInterval(-95 * 86_400)
        var descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)])
        descriptor.fetchLimit = 40_000
        return (try? env.modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let pinnedHeader { pinnedHeader }
                if !derived.ready {
                    loadingPlaceholder
                } else if hasAnyData {
                    if stats.hasGlucose { timeInRangeBar.appearTransition(delay: 0) }
                    statsGrid.appearTransition(delay: 0.06)
                    if let risk = derived.risk { riskCard(risk).appearTransition(delay: 0.09) }
                    if !derived.tagImpacts.isEmpty { tagImpactCard.appearTransition(delay: 0.10) }
                    if let insulin = insulinSummary { insulinBalanceCard(insulin).appearTransition(delay: 0.12) }
                    if !carbsByMeal.isEmpty { carbsByMealCard(carbsByMeal).appearTransition(delay: 0.18) }
                    if let overnight = overnightStats, overnight.hasGlucose { overnightCard(overnight).appearTransition(delay: 0.24) }
                    if periodTIRs.contains(where: \.hasData) { periodTIRCard.appearTransition(delay: 0.27) }
                    if dailyDays.count >= 2 { bestWorstDayCard.appearTransition(delay: 0.30) }
                    if tirTrend.count >= 2 { tirTrendCard.appearTransition(delay: 0.36) }
                    if gmiTrend.count >= 2 || !labResultsInRange.isEmpty {
                        gmiTrendCard.appearTransition(delay: 0.42)
                    }
                    if let reconciliation = latestReconciliation {
                        labReconciliationCard(reconciliation).appearTransition(delay: 0.44)
                    }
                    if let accuracy = sensorAccuracy {
                        sensorAccuracyCard(accuracy).appearTransition(delay: 0.48)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "Nothing to summarise",
                        message: "Add readings and entries to see statistics for this period."
                    )
                    .glassCard()
                }
            }
            .padding()
            .animation(.smooth, value: interval)
        }
        .sheet(isPresented: $showingLogLab) { LogLabA1cSheet() }
        .task(id: signature) {
            // The A1c reconciliation compares a lab result to the CGM estimate over
            // the ~90 days the lab reflects — wider than the selected interval — so
            // fetch that window on demand, and only when a lab actually exists.
            let reconReadings = labResults.first == nil ? [] : Self.fetchReconReadings(env)
            // The window immediately before this one, for the Clarity-style
            // "±X% vs the previous N days" delta. Skipped for Year — a second
            // ~100k-row fetch just for one line isn't worth the stall.
            let range = interval.dateRange()
            var previousReadings: [GlucoseReading]?
            if interval != .year {
                let duration = range.upperBound.timeIntervalSince(range.lowerBound)
                let prevLower = range.lowerBound.addingTimeInterval(-duration)
                let prevUpper = range.lowerBound
                let descriptor = FetchDescriptor<GlucoseReading>(
                    predicate: #Predicate { $0.isActive && $0.timestamp >= prevLower && $0.timestamp < prevUpper })
                previousReadings = (try? modelContext.fetch(descriptor)) ?? []
            }
            await derived.rebuild(
                glucose: glucose, insulin: insulin, carbs: carbs, activity: activity,
                observations: observations,
                labResults: labResults, reconReadings: reconReadings,
                healthExercise: healthExercise, previousReadings: previousReadings,
                range: range, thresholds: thresholds,
                periodTargets: env.preferences.periodTIRTargets,
                globalTargetPercent: env.preferences.glucoseGoals.targetTIRPercent)
        }
        // Pull the window's Apple Health exercise minutes; when they land the
        // signature changes and the rebuild re-runs to merge them into "Active time".
        .task(id: interval) {
            healthExercise = await env.healthKit.dailyMetric(.exercise, days: interval.dayCount)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Crunching your numbers…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .glassCard()
    }

    // MARK: Carbs by meal

    private func carbsByMealCard(_ items: [MealTypeCarbs]) -> some View {
        SectionCard("Carbs by meal", systemImage: "fork.knife") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack {
                        mealTypeText(item.mealType)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(item.totalGrams.formatted(.number.precision(.fractionLength(0)))) g")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.zoneHigh)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func mealTypeText(_ type: MealType) -> Text {
        switch type {
        case .breakfast: return Text("Breakfast")
        case .morningSnack: return Text("Snack")
        case .lunch: return Text("Lunch")
        case .dinner: return Text("Dinner")
        case .eveningSnack: return Text("Evening snack")
        }
    }

    // MARK: Overnight stability

    private func overnightCard(_ stats: PeriodStatistics) -> some View {
        SectionCard("Overnight (12–6 AM)", systemImage: "moon.stars.fill") {
            HStack(spacing: 16) {
                overnightMetric("Average", glucoseValue(stats.average), Theme.textPrimary)
                Divider().frame(height: 40).overlay(Theme.hairline)
                overnightMetric("Time in range", percent(stats.timeInRange), Theme.zoneInRange)
                Divider().frame(height: 40).overlay(Theme.hairline)
                overnightMetric("Time below", percent(stats.timeBelowRange), Theme.zoneCritical)
                Spacer()
            }
        }
    }

    private func overnightMetric(_ title: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Time in range by time of day

    private var periodTIRCard: some View {
        let rows = periodTIRs.filter(\.hasData)
        return SectionCard("Time in range by time of day", systemImage: "clock.badge.checkmark") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row in periodTIRRow(row) }
                if let takeaway = periodTIRTakeaway(rows) {
                    Text(takeaway)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func periodTIRRow(_ row: PeriodTIR) -> some View {
        let tint = row.met ? Theme.zoneInRange : Theme.zoneWarning
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(row.period.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if row.met {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.zoneInRange)
                        .accessibilityHidden(true)
                }
                Text(percent(row.timeInRange))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline).frame(height: 8)
                    Capsule().fill(tint)
                        .frame(width: max(geo.size.width * row.timeInRange, row.timeInRange > 0 ? 3 : 0), height: 8)
                    // Target marker.
                    Rectangle()
                        .fill(Theme.textTertiary)
                        .frame(width: 2, height: 13)
                        .offset(x: min(max(geo.size.width * row.targetFraction - 1, 0), geo.size.width - 2))
                }
            }
            .frame(height: 13)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.period.label): \(percent(row.timeInRange)) in range, target \(percent(row.targetFraction))\(row.met ? ", met" : "")")
    }

    private func periodTIRTakeaway(_ rows: [PeriodTIR]) -> String? {
        guard rows.count >= 2,
              let best = rows.max(by: { $0.timeInRange < $1.timeInRange }),
              let worst = rows.min(by: { $0.timeInRange < $1.timeInRange }),
              best.period != worst.period,
              best.timeInRange - worst.timeInRange >= 0.1 else { return nil }
        return String(localized: "Your \(best.period.label.lowercased()) is your steadiest window; \(worst.period.label.lowercased()) needs the most attention.")
    }

    // MARK: Best & toughest day

    @ViewBuilder
    private var bestWorstDayCard: some View {
        if let best = DailyBreakdown.best(dailyDays), let worst = DailyBreakdown.worst(dailyDays) {
            SectionCard("Best & toughest day", systemImage: "calendar.badge.clock") {
                HStack(spacing: 16) {
                    dayColumn(title: "Best day", day: best, tint: Theme.zoneInRange)
                    Divider().frame(height: 52).overlay(Theme.hairline)
                    dayColumn(title: "Toughest day", day: worst, tint: Theme.zoneHigh)
                    Spacer()
                }
            }
            .sheet(item: $selectedDay) { ref in
                dayDetailSheet(for: ref.day)
            }
        }
    }

    private func dayColumn(title: LocalizedStringKey, day: DayTIR, tint: Color) -> some View {
        Button {
            Haptics.play(.light)
            selectedDay = StatDayRef(day: day.day)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(percent(day.timeInRange))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                HStack(spacing: 3) {
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this day")
    }

    /// A day-detail sheet for one calendar day, filtering the windowed queries to
    /// that day so tapping the best/toughest day opens its full record.
    private func dayDetailSheet(for day: Date) -> some View {
        let calendar = Calendar.current
        func sameDay(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: day) }
        return CalendarDayDetailSheet(
            date: day,
            readings: glucose.filter { $0.isActive && sameDay($0.timestamp) },
            insulin: insulin.filter { sameDay($0.timestamp) },
            carbs: carbs.filter { sameDay($0.timestamp) },
            activity: activity.filter { sameDay($0.startTimestamp) },
            observations: observations.filter { sameDay($0.timestamp) },
            unit: unit,
            thresholds: thresholds,
            calendar: calendar
        )
    }

    // MARK: Insulin balance

    private func insulinBalanceCard(_ insulin: InsulinSummary) -> some View {
        let basalPct = (insulin.basalFraction * 100).formatted(.number.precision(.fractionLength(0))) + "%"
        let bolusPct = (insulin.bolusFraction * 100).formatted(.number.precision(.fractionLength(0))) + "%"
        let avg = insulin.averageDailyUnits.formatted(.number.precision(.fractionLength(1)))
        return SectionCard("Insulin balance", systemImage: "syringe.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(avg) U")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("avg / day")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        Theme.zoneWarning
                            .frame(width: max(geo.size.width * insulin.basalFraction, insulin.basalFraction > 0 ? 2 : 0))
                        Theme.accent
                            .frame(width: max(geo.size.width * insulin.bolusFraction, insulin.bolusFraction > 0 ? 2 : 0))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 14)
                HStack {
                    Text("Basal \(basalPct)")
                        .font(.caption2).foregroundStyle(Theme.zoneWarning)
                    Spacer()
                    Text("Bolus \(bolusPct)")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Time-in-range trend

    private var tirTrendCard: some View {
        SectionCard("Time in range trend", systemImage: "chart.line.uptrend.xyaxis") {
            Chart(tirTrend) { point in
                AreaMark(x: .value("Week", point.weekStart), y: .value("TIR", point.timeInRange))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.zoneInRange.opacity(0.16))
                LineMark(x: .value("Week", point.weekStart), y: .value("TIR", point.timeInRange))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.zoneInRange)
                PointMark(x: .value("Week", point.weekStart), y: .value("TIR", point.timeInRange))
                    .foregroundStyle(Theme.zoneInRange)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) {
                            Text((fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    // MARK: Estimated A1c trend (with lab A1c overlay)

    /// A small "＋ Log lab A1c" affordance shown in the trend card's header.
    private var logLabButton: some View {
        Button {
            Haptics.play(.selection)
            showingLogLab = true
        } label: {
            Label("Log lab A1c", systemImage: "plus.circle.fill")
                .font(.footnote.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .accessibilityHint("Record a clinic HbA1c result to compare against the estimate.")
    }

    private var gmiTrendCard: some View {
        SectionCard("Estimated A1c trend", systemImage: "chart.xyaxis.line",
                    accessory: AnyView(logLabButton)) {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(gmiTrend) { point in
                        LineMark(x: .value("Week", point.weekStart), y: .value("A1c", point.gmi),
                                 series: .value("Series", "Estimated"))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Week", point.weekStart), y: .value("A1c", point.gmi))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(50)
                    }
                    if let projection = a1cProjection, let last = gmiTrend.last {
                        let projectionDate = last.weekStart
                            .addingTimeInterval(A1cProjection.projectionDays * 86_400)
                        LineMark(x: .value("Week", last.weekStart), y: .value("A1c", last.gmi),
                                 series: .value("Series", "Projection"))
                            .foregroundStyle(Theme.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        LineMark(x: .value("Week", projectionDate),
                                 y: .value("A1c", projection.projectedA1cPercent),
                                 series: .value("Series", "Projection"))
                            .foregroundStyle(Theme.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        PointMark(x: .value("Week", projectionDate),
                                  y: .value("A1c", projection.projectedA1cPercent))
                            .foregroundStyle(Theme.textTertiary)
                            .symbolSize(40)
                    }
                    ForEach(labResultsInRange) { lab in
                        PointMark(x: .value("Lab date", lab.timestamp), y: .value("A1c", lab.value))
                            .foregroundStyle(Theme.zoneWarning)
                            .symbol(.diamond)
                            .symbolSize(150)
                            .annotation(position: .top, spacing: 1) {
                                Text(labA1cText(lab.value))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.zoneWarning)
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let gmi = value.as(Double.self) {
                                Text(gmi.formatted(.number.precision(.fractionLength(1))) + "%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            }
                        }
                    }
                }
                .frame(height: 150)

                HStack(spacing: 16) {
                    trendLegend(String(localized: "Estimated (GMI)"), color: Theme.accent)
                    trendLegend(String(localized: "Lab A1c"), color: Theme.zoneWarning)
                    if a1cProjection != nil {
                        trendLegend(String(localized: "Projection"), color: Theme.textTertiary)
                    }
                    Spacer()
                }

                if let projection = a1cProjection {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("If this trend holds, estimated A1c in ~3 months: \(projectedA1cText(projection.projectedA1cPercent))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("A projection, not a prediction — talk to your care team before changing therapy.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func projectedA1cText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func trendLegend(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func labA1cText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    // MARK: Lab vs estimate reconciliation

    /// Compares the most recent lab HbA1c against the CGM-derived estimate over
    /// the ~90 days it reflects, and explains the gap supportively.
    private func labReconciliationCard(_ r: A1cReconciliation) -> some View {
        let labText = labA1cText(r.labA1c)
        let estText = labA1cText(r.estimatedA1c)
        let gapText = (r.gap >= 0 ? "+" : "") + r.gap.formatted(.number.precision(.fractionLength(1)))
        let message = reconcileMessage(r)
        return SectionCard("Lab vs estimate", systemImage: "cross.case.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    reconcileFigure(title: "Lab A1c", value: labText, tint: Theme.zoneWarning)
                    reconcileFigure(title: "Estimated", value: estText, tint: Theme.accent)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Gap")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text("\(gapText) pts")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(r.alignment == .aligned ? Theme.zoneInRange : Theme.textPrimary)
                            .monospacedDigit()
                    }
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !r.estimateReliable {
                    Text("Sensor data was sparse across that period, so treat the estimate loosely.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("For context only — your lab test is the reference. Discuss any gap with your care team.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Lab A1c \(labText), estimated \(estText), gap \(gapText) points. \(message)")
        }
    }

    private func reconcileFigure(title: LocalizedStringKey, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func reconcileMessage(_ r: A1cReconciliation) -> String {
        switch r.alignment {
        case .aligned:
            return String(localized: "Your sensor estimate and your lab A1c line up closely — a good sign the CGM reflects your overall glucose well.")
        case .labHigher:
            return String(localized: "Your lab A1c came in a bit higher than the sensor estimate. This can happen with sparse readings, or simply how your body glycates — not necessarily a sensor issue.")
        case .labLower:
            return String(localized: "Your lab A1c came in a bit lower than the sensor estimate. Sensors sometimes read slightly high; the gap is worth noting but usually not a concern on its own.")
        }
    }

    // MARK: Sensor accuracy

    private func sensorAccuracyCard(_ accuracy: SensorAccuracyResult) -> some View {
        let mard = accuracy.meanAbsoluteRelativeDifferencePercent
        return SectionCard("Sensor accuracy", systemImage: "target") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mard.formatted(.number.precision(.fractionLength(1))) + "%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(mardTint(mard))
                    Text("MARD")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 16) {
                    accuracyMetric("Pairs", "\(accuracy.pairCount)")
                    Divider().frame(height: 40).overlay(Theme.hairline)
                    accuracyMetric("Avg difference",
                                   GlucoseFormatting.labeled(mgdL: accuracy.meanAbsoluteDifferenceMgdL, unit: unit))
                    Divider().frame(height: 40).overlay(Theme.hairline)
                    accuracyMetric("Within 15/15", percent(accuracy.withinISO15197Fraction))
                    Spacer()
                }

                Text(mardInterpretation(mard))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(mardTint(mard))

                Text("Compares your own finger-stick and manual meter entries with the nearest sensor reading within 15 minutes. Informational only — not a clinical accuracy rating.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func accuracyMetric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func mardInterpretation(_ mard: Double) -> String {
        if mard < 10 { return String(localized: "Excellent agreement between sensor and meter.") }
        if mard <= 15 { return String(localized: "Good agreement between sensor and meter.") }
        return String(localized: "Larger differences than typical — check sensor placement or calibrate per the manufacturer's instructions.")
    }

    private func mardTint(_ mard: Double) -> Color {
        if mard < 10 { return Theme.zoneInRange }
        if mard <= 15 { return Theme.zoneWarning }
        return Theme.zoneHigh
    }

    // MARK: Time-in-range card (Clarity-style, per the user's reference)

    /// The Dexcom Clarity layout the user asked for: a five-zone vertical bar
    /// with the percentages beside it ("In range" writ large), the change vs
    /// the previous equally long window, and the Day/Night target-range box
    /// when the night range is enabled.
    private var timeInRangeBar: some View {
        SectionCard(thresholds.nightModeEnabled ? "Time in range (custom)" : "Time in range",
                    systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 16) {
                // Say which window the numbers cover ("Last 24 hours", "Last
                // 7 days"…) — Day and Week can genuinely land on similar
                // percentages, and without this label that read as a bug.
                Text(verbatim: PrvitalString(interval.periodLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                HStack(alignment: .center, spacing: 18) {
                    verticalTIRBar
                    VStack(alignment: .leading, spacing: 10) {
                        zoneRow("Very high", stats.timeVeryHigh)
                        zoneRow("High", max(0, stats.timeAboveRange - stats.timeVeryHigh))
                        zoneRow("In range", stats.timeInRange, big: true)
                        zoneRow("Low", max(0, stats.timeBelowRange - stats.timeVeryLow))
                        zoneRow("Very low", stats.timeVeryLow)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Time in range \(percent(stats.timeInRange)), "
                    + "below \(percent(stats.timeBelowRange)), "
                    + "above \(percent(stats.timeAboveRange))"
                )

                tirChangeLine
                targetRangeBox
            }
        }
    }

    /// The stacked five-zone bar, very high at the top, very low at the bottom.
    private var verticalTIRBar: some View {
        let height: CGFloat = 210
        return VStack(spacing: 3) {
            barSlice(stats.timeVeryHigh, height: height, color: GlucoseZone.veryHigh.color)
            barSlice(max(0, stats.timeAboveRange - stats.timeVeryHigh), height: height, color: GlucoseZone.high.color)
            barSlice(stats.timeInRange, height: height, color: GlucoseZone.inRange.color)
            barSlice(max(0, stats.timeBelowRange - stats.timeVeryLow), height: height, color: GlucoseZone.low.color)
            barSlice(stats.timeVeryLow, height: height, color: GlucoseZone.veryLow.color)
        }
        .frame(width: 54)
        .accessibilityHidden(true)
    }

    private func barSlice(_ fraction: Double, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            // A zone that occurred at all keeps a visible sliver, like the
            // reference's thin "<1%" strips; an absent zone takes no space.
            .frame(height: fraction > 0 ? max(6, height * fraction) : 0)
    }

    private func zoneRow(_ key: LocalizedStringKey, _ value: Double, big: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(zonePercent(value))
                .font(big ? .system(size: 30, weight: .bold, design: .rounded)
                          : .system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(key)
                .font(big ? .title3.weight(.semibold) : .subheadline)
                .foregroundStyle(big ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    /// "16 %" — but a present-yet-tiny zone reads "<1 %", Clarity-style, so a
    /// single spike never rounds away to a dishonest 0.
    private func zonePercent(_ value: Double) -> String {
        if value > 0 && value < 0.01 { return String(localized: "<1 %") }
        return percent(value)
    }

    /// "±X% vs the previous day/N days" — only when both windows have glucose.
    /// The figure is the *window's* length (Day compares against the previous
    /// 24 hours) — `interval.dayCount` is Health-fetch padding, not for display.
    @ViewBuilder
    private var tirChangeLine: some View {
        if let previous = derived.previousPeriodTIR, stats.hasGlucose {
            let points = Int(((stats.timeInRange - previous) * 100).rounded())
            let signed = points > 0 ? "+\(points) %" : "\(points) %"
            let tint: Color = points > 0 ? Theme.zoneInRange
                : (points < 0 ? Theme.zoneWarning : Theme.textSecondary)
            Label {
                Group {
                    if interval == .day {
                        Text("\(signed) change vs the previous 24 hours")
                    } else {
                        Text("\(signed) change vs the previous \(interval == .week ? 7 : 30) days")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            } icon: {
                Image(systemName: points > 0 ? "arrow.up.right" : (points < 0 ? "arrow.down.right" : "arrow.right"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tint)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The reference's "Target Range" box: Day + Night rows when the night
    /// range is on, a single all-day row otherwise.
    private var targetRangeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target range")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            if thresholds.nightModeEnabled {
                targetRangeRow(title: "Day",
                               window: windowText(from: thresholds.nightEndMinute, to: thresholds.nightStartMinute),
                               lower: thresholds.targetLower, upper: thresholds.targetUpper)
                Divider().overlay(Theme.hairline)
                targetRangeRow(title: "Night",
                               window: windowText(from: thresholds.nightStartMinute, to: thresholds.nightEndMinute),
                               lower: thresholds.nightTargetLower, upper: thresholds.nightTargetUpper)
            } else {
                targetRangeRow(title: nil, window: nil,
                               lower: thresholds.targetLower, upper: thresholds.targetUpper)
            }
        }
        .padding(14)
        .background(Theme.textPrimary.opacity(0.05), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func targetRangeRow(title: LocalizedStringKey?, window: String?,
                                lower: Double, upper: Double) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let window {
                    Text(window)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(GlucoseFormatting.string(mgdL: lower, unit: unit)) – "
                 + "\(GlucoseFormatting.string(mgdL: upper, unit: unit)) \(unit.rawValue)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func windowText(from startMinute: Int, to endMinute: Int) -> String {
        "\(timeText(startMinute)) – \(timeText(endMinute))"
    }

    private func timeText(_ minutesFromMidnight: Int) -> String {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .minute, value: minutesFromMidnight, to: base) ?? base
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Glycaemic risk

    /// The clinic-grade risk indices (GRI headline + LBGI/HBGI/MAGE rows) that
    /// Clarity/Glooko print — computed with the fixed clinical cutoffs, so the
    /// figures match what a doctor's report would say.
    private func riskCard(_ risk: GlycemicRisk) -> some View {
        SectionCard("Glycaemic risk", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glycemia Risk Index (GRI)")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                        Text(verbatim: "\(Int(risk.gri.rounded()))")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(griColor(risk.band))
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(griBandLabel(risk.band))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(griColor(risk.band))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(griColor(risk.band).opacity(0.14), in: .capsule)
                }
                griScale(risk.gri)

                VStack(spacing: 8) {
                    riskRow(title: "Hypo risk (LBGI)",
                            value: risk.lbgi.formatted(.number.precision(.fractionLength(1))),
                            severity: lbgiSeverity(risk.lbgi))
                    riskRow(title: "Hyper risk (HBGI)",
                            value: risk.hbgi.formatted(.number.precision(.fractionLength(1))),
                            severity: hbgiSeverity(risk.hbgi))
                    riskRow(title: "Swing size (MAGE)",
                            value: GlucoseFormatting.labeled(mgdL: risk.mage, unit: unit),
                            severity: nil)
                }

                Text("Computed with the fixed clinical cutoffs (54–70–180–250 mg/dL), so these figures match clinic reports regardless of your personal target range.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The 0–100 GRI strip with the published quintile bands and a marker.
    private func griScale(_ gri: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(GlycemicRisk.Band.allCases.enumerated()), id: \.offset) { _, band in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(griColor(band).opacity(0.35))
                    }
                }
                Circle()
                    .fill(Theme.textPrimary)
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: max(0, min(width - 14, width * gri / 100 - 7)))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func riskRow(title: LocalizedStringKey, value: String,
                         severity: (label: LocalizedStringKey, color: Color)?) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if let severity {
                Text(severity.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severity.color)
            }
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func griColor(_ band: GlycemicRisk.Band) -> Color {
        switch band {
        case .a: return Theme.zoneInRange
        case .b: return Theme.zoneInRange
        case .c: return Theme.zoneHigh
        case .d: return Theme.zoneWarning
        case .e: return Theme.zoneCritical
        }
    }

    private func griBandLabel(_ band: GlycemicRisk.Band) -> LocalizedStringKey {
        switch band {
        case .a: return "Very low risk"
        case .b: return "Low risk"
        case .c: return "Moderate risk"
        case .d: return "High risk"
        case .e: return "Very high risk"
        }
    }

    // MARK: Tag impact

    /// "Life vs glucose": time-in-range on the days carrying each quick tag,
    /// against the window's other days — the mySugr trick of making the diary
    /// answer questions ("what does stress do to me?").
    private var tagImpactCard: some View {
        SectionCard("Tags & your glucose", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(derived.tagImpacts) { impact in
                    HStack(spacing: 10) {
                        Image(systemName: impact.tag.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 24)
                            .background(Theme.accentSoft, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(impact.tag.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(impact.dayCount) days")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: percent(impact.taggedTIR))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                            if let delta = impact.delta {
                                let points = Int((delta * 100).rounded())
                                Text(verbatim: points >= 0 ? "+\(points) %" : "\(points) %")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(points >= 0 ? Theme.zoneInRange : Theme.zoneWarning)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Time in range on days with each tag, and how it differs from your other days.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func lbgiSeverity(_ lbgi: Double) -> (LocalizedStringKey, Color) {
        switch lbgi {
        case ..<1.1: return ("Minimal", Theme.zoneInRange)
        case ..<2.5: return ("Low", Theme.zoneInRange)
        case ..<5: return ("Moderate", Theme.zoneWarning)
        default: return ("High", Theme.zoneCritical)
        }
    }

    private func hbgiSeverity(_ hbgi: Double) -> (LocalizedStringKey, Color) {
        switch hbgi {
        case ..<4.5: return ("Low", Theme.zoneInRange)
        case ..<9: return ("Moderate", Theme.zoneWarning)
        default: return ("High", Theme.zoneCritical)
        }
    }

    // MARK: Stat grid

    private var statsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(title: "Average", value: glucoseValue(stats.average),
                     caption: unit.rawValue, systemImage: "drop.fill")
            StatTile(title: "Minimum", value: glucoseValue(stats.minimum),
                     caption: unit.rawValue, tint: Theme.zoneWarning, systemImage: "arrow.down")
            StatTile(title: "Maximum", value: glucoseValue(stats.maximum),
                     caption: unit.rawValue, tint: Theme.zoneHigh, systemImage: "arrow.up")

            StatTile(title: "Time in range", value: percentOrDash(stats.timeInRange, stats.hasGlucose),
                     caption: String(localized: "Target band"), tint: Theme.zoneInRange, systemImage: "target")
            StatTile(title: "Tight range", value: percentOrDash(stats.timeInTightRange, stats.hasGlucose),
                     caption: String(localized: "70–140 mg/dL"), tint: Theme.zoneInRange, systemImage: "scope")
            StatTile(title: "Time above", value: percentOrDash(stats.timeAboveRange, stats.hasGlucose),
                     caption: String(localized: "Above target"), tint: Theme.zoneHigh, systemImage: "arrow.up.right")
            StatTile(title: "Time below", value: percentOrDash(stats.timeBelowRange, stats.hasGlucose),
                     caption: String(localized: "Below target"), tint: Theme.zoneCritical, systemImage: "arrow.down.right")

            StatTile(title: "eA1c / GMI", value: gmiValue,
                     caption: String(localized: "Estimated A1c"), systemImage: "waveform.path.ecg")
            StatTile(title: "Variability", value: percentOrDash(stats.coefficientOfVariation, stats.hasGlucose),
                     caption: String(localized: "CV"), systemImage: "chart.line.uptrend.xyaxis")
            StatTile(title: "Std deviation", value: glucoseValue(stats.standardDeviation),
                     caption: unit.rawValue, systemImage: "plusminus")

            StatTile(title: "Hypo events", value: stats.hasGlucose ? "\(stats.hypoEvents)" : "—",
                     caption: String(localized: "Low excursions"), tint: Theme.zoneCritical, systemImage: "exclamationmark.triangle")
            StatTile(title: "Hyper events", value: stats.hasGlucose ? "\(stats.hyperEvents)" : "—",
                     caption: String(localized: "High excursions"), tint: Theme.zoneHigh, systemImage: "exclamationmark.triangle")

            StatTile(title: "Avg low recovery",
                     value: hypoRecovery.map { String(localized: "\(Int($0.averageMinutes.rounded())) min") } ?? "—",
                     caption: String(localized: "Time back in range"), tint: Theme.zoneWarning, systemImage: "arrow.uturn.up")

            StatTile(title: "Longest sensor gap",
                     value: dataGaps.map { gapText($0.longestGapMinutes) } ?? "—",
                     caption: dataGaps.map { String(localized: "\($0.gapCount) gaps over 30 min") } ?? String(localized: "No gaps"),
                     tint: Theme.zoneWarning, systemImage: "sensor.tag.radiowaves.forward.fill")

            StatTile(title: "Total bolus", value: String(localized: "\(stats.totalBolusUnits.formatted()) U"),
                     caption: String(localized: "Rapid-acting"), tint: Theme.accent, systemImage: "syringe.fill")
            StatTile(title: "Total basal", value: String(localized: "\(stats.totalBasalUnits.formatted()) U"),
                     caption: String(localized: "Long-acting"), tint: Theme.accent, systemImage: "syringe")

            StatTile(title: "Total carbs", value: String(localized: "\(stats.totalCarbGrams.formatted()) g"),
                     caption: stats.mealCount == 1
                         ? String(localized: "1 meal")
                         : String(localized: "\(stats.mealCount) meals"),
                     tint: Theme.zoneHigh, systemImage: "fork.knife")
            StatTile(title: "Meals", value: "\(stats.mealCount)",
                     caption: String(localized: "Logged"), tint: Theme.zoneHigh, systemImage: "list.bullet")

            StatTile(title: "Activity", value: String(localized: "\(activityMinutes) min"),
                     caption: String(localized: "Active time"), tint: Theme.zoneInRange, systemImage: "figure.walk")
        }
    }

    // MARK: Value formatting

    private func glucoseValue(_ mgdL: Double) -> String {
        stats.hasGlucose ? GlucoseFormatting.string(mgdL: mgdL, unit: unit) : "—"
    }

    private var gmiValue: String {
        guard stats.hasGlucose else { return "—" }
        return stats.glucoseManagementIndicator
            .formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// Percentage rendered as `value * 100` rounded, suffixed with `%`.
    private func percent(_ fraction: Double) -> String {
        "\((fraction * 100).rounded().formatted(.number.precision(.fractionLength(0))))%"
    }

    private func percentOrDash(_ fraction: Double, _ available: Bool) -> String {
        available ? percent(fraction) : "—"
    }

    /// Duration in minutes rendered compactly ("45 min" or "2h 5m").
    private func gapText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 90 { return String(localized: "\(total) min") }
        return String(localized: "\(total / 60)h \(total % 60)m")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return StatisticsView(interval: .constant(.week))
        .environment(env)
        .modelContainer(env.modelContainer)
}

/// Records a real clinic HbA1c result, saved straight into the SwiftData store
/// via the view's `modelContext` (no dedicated store), so it appears on the
/// estimated-A1c trend for comparison.
struct LogLabA1cSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Sensible starting point within the plausible HbA1c range.
    @State private var value: Double = 7.0
    @State private var date = Date()
    @State private var note = ""

    private var valueText: String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(valueText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: value)
                        Spacer()
                        Stepper("A1c", value: $value, in: 4.0...15.0, step: 0.1)
                            .labelsHidden()
                    }
                } header: {
                    Text("Lab HbA1c")
                } footer: {
                    Text("Enter the HbA1c from your clinic lab report. Prvital plots it on your estimated-A1c trend so you can see how the CGM estimate compares to the blood test.")
                }
                Section {
                    DatePicker("Test date", selection: $date,
                               in: ...Date(), displayedComponents: .date)
                }
                Section("Note") {
                    TextField("Optional (e.g. clinic, fasting)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log lab A1c")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(value <= 0)
                }
            }
        }
    }

    private func save() {
        let result = LabResult(value: value, timestamp: date, note: note.isEmpty ? nil : note)
        modelContext.insert(result)
        try? modelContext.save()
        Haptics.play(.success)
        dismiss()
    }
}

// MARK: - Derived (computed once per data change, off the render path)

/// A cheap fingerprint of the Statistics inputs. `.task(id:)` reruns the rebuild
/// only when this changes, so scrolls/animations/sheet toggles never recompute.
struct StatisticsSignature: Equatable {
    let interval: InsightsInterval
    let glucose: Int
    let insulin: Int
    let carbs: Int
    let activity: Int
    let observations: Int
    let labs: Int
    let newest: Date?
    let thresholds: GlucoseThresholds
    let periodTargets: PeriodTIRTargets
    let globalTargetPercent: Double
    let healthExerciseDays: Int
    let healthExerciseTotal: Int
}

/// Holds the prepared statistics for the current window. Rebuilt once per data
/// change on the main actor (SwiftData objects are main-actor bound), with a
/// yield after the initial filter so the pane can paint its loading state before
/// the heavier analyzers run. Behaviour-identical to the former per-render
/// computed properties — only *when* and *how often* they run has changed.
@MainActor
@Observable
final class StatisticsDerived {
    var ready = false
    var stats = PeriodStatistics()
    /// Active minutes for the window — logged workouts merged with Apple Health's
    /// exercise total (per-day max, so the Watch's activity shows even with no
    /// logged sessions and workout time is never double-counted).
    var activityMinutes = 0
    var hasAnyData = false
    var hypoRecovery: HypoRecoveryStats?
    var gmiTrend: [GMIPoint] = []
    var labResultsInRange: [LabResult] = []
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
    /// Time-in-range over the equally long window immediately BEFORE this one
    /// (nil when that window has no glucose, or for Year, where fetching a
    /// second year just for one delta line isn't worth it) — drives the
    /// Clarity-style "±X% vs the previous N days" line.
    var previousPeriodTIR: Double?
    /// Clinical risk indices (GRI, LBGI/HBGI, MAGE); nil below 24 readings.
    var risk: GlycemicRisk?
    /// TIR on tagged vs untagged days, for the tags used in this window.
    var tagImpacts: [TagImpact] = []

    func rebuild(
        glucose: [GlucoseReading], insulin: [InsulinDose], carbs: [CarbEntry],
        activity: [ActivityEntry], observations: [ObservationEntry],
        labResults: [LabResult], reconReadings: [GlucoseReading],
        healthExercise: [DailyMetric], previousReadings: [GlucoseReading]?,
        range: ClosedRange<Date>,
        thresholds: GlucoseThresholds, periodTargets: PeriodTIRTargets,
        globalTargetPercent: Double
    ) async {
        let active = glucose.filter { $0.isActive && range.contains($0.timestamp) }
        let fInsulin = insulin.filter { range.contains($0.timestamp) }
        let fCarbs = carbs.filter { range.contains($0.timestamp) }
        let fActivity = activity.filter { range.contains($0.startTimestamp) }
        // Sensor accuracy is fed *all* readings in range (incl. conflict-superseded
        // ones), matching the previous behaviour.
        let inRangeGlucose = glucose.filter { range.contains($0.timestamp) }
        let labsInRange = labResults.filter { range.contains($0.timestamp) }

        // Let the loading placeholder paint before the heavier analyzers run.
        await Task.yield()

        let base = StatisticsEngine.glucose(active, thresholds: thresholds)
        let summary = StatisticsEngine.enrich(base, insulin: fInsulin, carbs: fCarbs, activity: fActivity)
        let activityMins = Self.mergedActivityMinutes(logged: fActivity, health: healthExercise, range: range)
        let anyData = summary.hasGlucose || !fInsulin.isEmpty || !fCarbs.isEmpty
            || !fActivity.isEmpty || activityMins > 0

        let gmi = GMITrend.weekly(active)
        // Reconciliation uses the full reading history (not the window) so its
        // ~90-day comparison is always the clinically correct one.
        let recon: A1cReconciliation? = labResults.first.flatMap {
            A1cReconciler.reconcile(lab: $0, readings: reconReadings, thresholds: thresholds)
        }
        let projection: A1cProjectionResult? = {
            guard let p = A1cProjection.project(gmi), p.confidence == .ok else { return nil }
            return p
        }()
        let sensor = SensorAccuracyAnalyzer.analyze(inRangeGlucose)
        let tir = TIRTrend.weekly(active, thresholds: thresholds)
        let gaps = DataGapDetector.analyze(active)
        let insulinSum = InsulinAnalyzer.summary(fInsulin)
        let days = DailyBreakdown.perDay(active, thresholds: thresholds)
        let overnight = OvernightStability.analyze(active, thresholds: thresholds)
        let byMeal = CarbDistribution.byMealType(fCarbs)
        let hypo = HypoRecoveryAnalyzer.analyze(active, thresholds: thresholds)
        let pTIRs = PeriodTIRAnalyzer.breakdown(
            active, thresholds: thresholds,
            targets: periodTargets, globalTargetPercent: globalTargetPercent)
        let previousTIR: Double? = previousReadings.flatMap { readings in
            let prev = StatisticsEngine.glucose(readings.filter(\.isActive), thresholds: thresholds)
            return prev.hasGlucose ? prev.timeInRange : nil
        }
        let riskIndices = GlycemicRiskEngine.compute(active)
        let fObservations = observations.filter { range.contains($0.timestamp) }
        let tagStats = TagImpactAnalyzer.analyze(
            readings: active, carbs: fCarbs, observations: fObservations,
            thresholds: thresholds)

        self.previousPeriodTIR = previousTIR
        self.risk = riskIndices
        self.tagImpacts = tagStats
        self.stats = summary
        self.activityMinutes = activityMins
        self.hasAnyData = anyData
        self.hypoRecovery = hypo
        self.gmiTrend = gmi
        self.labResultsInRange = labsInRange
        self.latestReconciliation = recon
        self.a1cProjection = projection
        self.sensorAccuracy = sensor
        self.tirTrend = tir
        self.dataGaps = gaps
        self.insulinSummary = insulinSum
        self.dailyDays = days
        self.overnightStats = overnight
        self.carbsByMeal = byMeal
        self.periodTIRs = pTIRs
        self.ready = true
    }

    /// Total active minutes over the window: per day, the LARGER of logged workout
    /// minutes and Apple Health's exercise total (never the sum — Apple Health's
    /// `appleExerciseTime` already counts logged workout time), then summed.
    static func mergedActivityMinutes(logged: [ActivityEntry], health: [DailyMetric],
                                      range: ClosedRange<Date>) -> Int {
        let calendar = Calendar.current
        var loggedByDay: [Date: Double] = [:]
        for entry in logged {
            loggedByDay[calendar.startOfDay(for: entry.startTimestamp), default: 0] += Double(entry.durationMinutes)
        }
        var healthByDay: [Date: Double] = [:]
        let lowerDay = calendar.startOfDay(for: range.lowerBound)
        for metric in health where metric.day >= lowerDay {
            healthByDay[calendar.startOfDay(for: metric.day)] = metric.value
        }
        let days = Set(loggedByDay.keys).union(healthByDay.keys)
        let total = days.reduce(0.0) { $0 + max(loggedByDay[$1] ?? 0, healthByDay[$1] ?? 0) }
        return Int(total.rounded())
    }
}

#Preview("Log lab A1c") {
    LogLabA1cSheet()
        .modelContainer(AppEnvironment.preview().modelContainer)
}
