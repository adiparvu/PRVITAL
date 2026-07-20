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

    @State private var interval: InsightsInterval = .week

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
                    if stats.hasGlucose { timeInRangeBar }
                    statsGrid
                    if let insulin = insulinSummary { insulinBalanceCard(insulin) }
                    if !carbsByMeal.isEmpty { carbsByMealCard(carbsByMeal) }
                    if let overnight = overnightStats, overnight.hasGlucose { overnightCard(overnight) }
                    if dailyDays.count >= 2 { bestWorstDayCard }
                    if gmiTrend.count >= 2 { gmiTrendCard }
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
        }
        .background(Theme.background)
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
                        Theme.accent.opacity(0.55)
                            .frame(width: max(geo.size.width * insulin.basalFraction, insulin.basalFraction > 0 ? 2 : 0))
                        Theme.accent
                            .frame(width: max(geo.size.width * insulin.bolusFraction, insulin.bolusFraction > 0 ? 2 : 0))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 14)
                HStack {
                    Text("Basal \(basalPct)")
                        .font(.caption2).foregroundStyle(Theme.accent.opacity(0.85))
                    Spacer()
                    Text("Bolus \(bolusPct)")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Estimated A1c trend

    private var gmiTrendCard: some View {
        SectionCard("Estimated A1c trend", systemImage: "chart.xyaxis.line") {
            Chart(gmiTrend) { point in
                LineMark(x: .value("Week", point.weekStart), y: .value("GMI", point.gmi))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent)
                PointMark(x: .value("Week", point.weekStart), y: .value("GMI", point.gmi))
                    .foregroundStyle(Theme.accent)
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
        }
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
