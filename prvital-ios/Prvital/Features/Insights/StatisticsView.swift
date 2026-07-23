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

    var body: some View {
        StatisticsContent(interval: interval).id(interval)
    }
}

struct StatisticsContent: View {
    @Environment(AppEnvironment.self) private var env

    let interval: InsightsInterval

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]
    @Query(sort: \LabResult.timestamp, order: .reverse) private var labResults: [LabResult]

    init(interval: InsightsInterval) {
        self.interval = interval
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
            activity: activity.count, labs: labResults.count,
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
                if !derived.ready {
                    loadingPlaceholder
                } else if hasAnyData {
                    if stats.hasGlucose { timeInRangeBar.appearTransition(delay: 0) }
                    statsGrid.appearTransition(delay: 0.06)
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
        .background(Theme.background)
        .sheet(isPresented: $showingLogLab) { LogLabA1cSheet() }
        .task(id: signature) {
            // The A1c reconciliation compares a lab result to the CGM estimate over
            // the ~90 days the lab reflects — wider than the selected interval — so
            // fetch that window on demand, and only when a lab actually exists.
            let reconReadings = labResults.first == nil ? [] : Self.fetchReconReadings(env)
            await derived.rebuild(
                glucose: glucose, insulin: insulin, carbs: carbs, activity: activity,
                labResults: labResults, reconReadings: reconReadings,
                healthExercise: healthExercise,
                range: interval.dateRange(), thresholds: thresholds,
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

    // MARK: Time-in-range bar

    private var timeInRangeBar: some View {
        SectionCard("Time in range", systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        segment(width: geo.size.width * stats.timeBelowRange, color: Theme.zoneCritical)
                        segment(width: geo.size.width * stats.timeInRange, color: Theme.zoneInRange)
                        segment(width: geo.size.width * stats.timeAboveRange, color: Theme.zoneHigh)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Time in range \(percent(stats.timeInRange)), "
                    + "below \(percent(stats.timeBelowRange)), "
                    + "above \(percent(stats.timeAboveRange))"
                )

                HStack(spacing: 16) {
                    legendDot(String(localized: "Below"), value: stats.timeBelowRange, color: Theme.zoneCritical)
                    legendDot(String(localized: "In range"), value: stats.timeInRange, color: Theme.zoneInRange)
                    legendDot(String(localized: "Above"), value: stats.timeAboveRange, color: Theme.zoneHigh)
                }
            }
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func legendDot(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
                Text(percent(value))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(percent(value))")
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

    func rebuild(
        glucose: [GlucoseReading], insulin: [InsulinDose], carbs: [CarbEntry],
        activity: [ActivityEntry], labResults: [LabResult], reconReadings: [GlucoseReading],
        healthExercise: [DailyMetric],
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
