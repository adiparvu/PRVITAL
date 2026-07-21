import SwiftUI
import SwiftData
import Charts

/// The numeric pane of Insights: a computed `PeriodStatistics` for the selected
/// interval, rendered as a grid of `StatTile`s plus a Time-in-Range stacked bar.
/// Glucose figures are always formatted through `GlucoseFormatting` in the user's
/// unit; percentages use the `value * 100` rounding rule.
struct StatisticsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var glucose: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]
    @Query(sort: \LabResult.timestamp, order: .reverse) private var labResults: [LabResult]

    @State private var interval: InsightsInterval = .week
    @State private var showingLogLab = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var range: ClosedRange<Date> { interval.dateRange() }

    // MARK: Filtered data

    private var activeReadings: [GlucoseReading] {
        glucose.filter { $0.isActive && range.contains($0.timestamp) }
    }
    private var filteredInsulin: [InsulinDose] {
        insulin.filter { range.contains($0.timestamp) }
    }
    private var filteredCarbs: [CarbEntry] {
        carbs.filter { range.contains($0.timestamp) }
    }
    private var filteredActivity: [ActivityEntry] {
        activity.filter { range.contains($0.startTimestamp) }
    }

    /// The enriched summary for the current window.
    private var stats: PeriodStatistics {
        let base = StatisticsEngine.glucose(activeReadings, thresholds: thresholds)
        return StatisticsEngine.enrich(
            base,
            insulin: filteredInsulin,
            carbs: filteredCarbs,
            activity: filteredActivity
        )
    }

    private var hasAnyData: Bool {
        stats.hasGlucose
            || !filteredInsulin.isEmpty
            || !filteredCarbs.isEmpty
            || !filteredActivity.isEmpty
    }

    private var hypoRecovery: HypoRecoveryStats? {
        HypoRecoveryAnalyzer.analyze(activeReadings, thresholds: thresholds)
    }

    private var gmiTrend: [GMIPoint] {
        GMITrend.weekly(activeReadings)
    }

    /// Real clinic HbA1c results dated within the selected window — plotted over
    /// the estimated-A1c trend for comparison.
    private var labResultsInRange: [LabResult] {
        labResults.filter { range.contains($0.timestamp) }
    }

    /// Least-squares trajectory of the weekly GMI series, kept only when the
    /// fit is confident (enough weeks, small residuals) — a shaky trend line
    /// is worse than none.
    private var a1cProjection: A1cProjectionResult? {
        guard let projection = A1cProjection.project(gmiTrend),
              projection.confidence == .ok else { return nil }
        return projection
    }

    /// Personal sensor-vs-meter agreement for the window. Fed *all* readings in
    /// range — including conflict-superseded ones — because a finger stick that
    /// lost conflict resolution to a near-simultaneous sensor value is exactly
    /// the comparison pair the analyzer needs.
    private var sensorAccuracy: SensorAccuracyResult? {
        SensorAccuracyAnalyzer.analyze(glucose.filter { range.contains($0.timestamp) })
    }

    private var tirTrend: [TIRPoint] {
        TIRTrend.weekly(activeReadings, thresholds: thresholds)
    }

    private var dataGaps: GapStats? {
        DataGapDetector.analyze(activeReadings)
    }

    private var insulinSummary: InsulinSummary? {
        InsulinAnalyzer.summary(filteredInsulin)
    }

    private var dailyDays: [DayTIR] {
        DailyBreakdown.perDay(activeReadings, thresholds: thresholds)
    }

    private var overnightStats: PeriodStatistics? {
        OvernightStability.analyze(activeReadings, thresholds: thresholds)
    }

    private var carbsByMeal: [MealTypeCarbs] {
        CarbDistribution.byMealType(filteredCarbs)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Interval", selection: $interval) {
                    ForEach(InsightsInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: interval) { _, _ in Haptics.play(.selection) }

                if hasAnyData {
                    if stats.hasGlucose { timeInRangeBar.appearTransition(delay: 0) }
                    statsGrid.appearTransition(delay: 0.06)
                    if let insulin = insulinSummary { insulinBalanceCard(insulin).appearTransition(delay: 0.12) }
                    if !carbsByMeal.isEmpty { carbsByMealCard(carbsByMeal).appearTransition(delay: 0.18) }
                    if let overnight = overnightStats, overnight.hasGlucose { overnightCard(overnight).appearTransition(delay: 0.24) }
                    if dailyDays.count >= 2 { bestWorstDayCard.appearTransition(delay: 0.30) }
                    if tirTrend.count >= 2 { tirTrendCard.appearTransition(delay: 0.36) }
                    if gmiTrend.count >= 2 || !labResultsInRange.isEmpty {
                        gmiTrendCard.appearTransition(delay: 0.42)
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
        }
    }

    private func dayColumn(title: LocalizedStringKey, day: DayTIR, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(percent(day.timeInRange))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
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
                    trendLegend("Estimated (GMI)", color: Theme.accent)
                    trendLegend("Lab A1c", color: Theme.zoneWarning)
                    if a1cProjection != nil {
                        trendLegend("Projection", color: Theme.textTertiary)
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
        if mard < 10 { return "Excellent agreement between sensor and meter." }
        if mard <= 15 { return "Good agreement between sensor and meter." }
        return "Larger differences than typical — check sensor placement or calibrate per the manufacturer's instructions."
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
                    legendDot("Below", value: stats.timeBelowRange, color: Theme.zoneCritical)
                    legendDot("In range", value: stats.timeInRange, color: Theme.zoneInRange)
                    legendDot("Above", value: stats.timeAboveRange, color: Theme.zoneHigh)
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
                     caption: "Target band", tint: Theme.zoneInRange, systemImage: "target")
            StatTile(title: "Tight range", value: percentOrDash(stats.timeInTightRange, stats.hasGlucose),
                     caption: "70–140 mg/dL", tint: Theme.zoneInRange, systemImage: "scope")
            StatTile(title: "Time above", value: percentOrDash(stats.timeAboveRange, stats.hasGlucose),
                     caption: "Above target", tint: Theme.zoneHigh, systemImage: "arrow.up.right")
            StatTile(title: "Time below", value: percentOrDash(stats.timeBelowRange, stats.hasGlucose),
                     caption: "Below target", tint: Theme.zoneCritical, systemImage: "arrow.down.right")

            StatTile(title: "eA1c / GMI", value: gmiValue,
                     caption: "Estimated A1c", systemImage: "waveform.path.ecg")
            StatTile(title: "Variability", value: percentOrDash(stats.coefficientOfVariation, stats.hasGlucose),
                     caption: "CV", systemImage: "chart.line.uptrend.xyaxis")
            StatTile(title: "Std deviation", value: glucoseValue(stats.standardDeviation),
                     caption: unit.rawValue, systemImage: "plusminus")

            StatTile(title: "Hypo events", value: stats.hasGlucose ? "\(stats.hypoEvents)" : "—",
                     caption: "Low excursions", tint: Theme.zoneCritical, systemImage: "exclamationmark.triangle")
            StatTile(title: "Hyper events", value: stats.hasGlucose ? "\(stats.hyperEvents)" : "—",
                     caption: "High excursions", tint: Theme.zoneHigh, systemImage: "exclamationmark.triangle")

            StatTile(title: "Avg low recovery",
                     value: hypoRecovery.map { "\(Int($0.averageMinutes.rounded())) min" } ?? "—",
                     caption: "Time back in range", tint: Theme.zoneWarning, systemImage: "arrow.uturn.up")

            StatTile(title: "Longest sensor gap",
                     value: dataGaps.map { gapText($0.longestGapMinutes) } ?? "—",
                     caption: dataGaps.map { "\($0.gapCount) gaps over 30 min" } ?? "No gaps",
                     tint: Theme.zoneWarning, systemImage: "sensor.tag.radiowaves.forward.fill")

            StatTile(title: "Total bolus", value: "\(stats.totalBolusUnits.formatted()) U",
                     caption: "Rapid-acting", tint: Theme.accent, systemImage: "syringe.fill")
            StatTile(title: "Total basal", value: "\(stats.totalBasalUnits.formatted()) U",
                     caption: "Long-acting", tint: Theme.accent, systemImage: "syringe")

            StatTile(title: "Total carbs", value: "\(stats.totalCarbGrams.formatted()) g",
                     caption: "\(stats.mealCount) meal\(stats.mealCount == 1 ? "" : "s")",
                     tint: Theme.zoneHigh, systemImage: "fork.knife")
            StatTile(title: "Meals", value: "\(stats.mealCount)",
                     caption: "Logged", tint: Theme.zoneHigh, systemImage: "list.bullet")

            StatTile(title: "Activity", value: "\(stats.activityMinutes) min",
                     caption: "Active time", tint: Theme.zoneInRange, systemImage: "figure.walk")
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
        if total < 90 { return "\(total) min" }
        return "\(total / 60)h \(total % 60)m"
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return StatisticsView()
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

#Preview("Log lab A1c") {
    LogLabA1cSheet()
        .modelContainer(AppEnvironment.preview().modelContainer)
}
