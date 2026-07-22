import SwiftUI
import SwiftData
import Charts

/// The visual pane of Insights: glucose trend plus daily insulin, carbohydrate
/// and activity bars for the selected interval. All reads are plain `@Query`s
/// filtered to `interval.dateRange()` in computed vars, per the data guidelines.
struct ChartsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]

    /// The widest interval is one year, so the queries never need more than ~370
    /// days. Windowing them here means a synced (or freshly imported) 100k+-row
    /// table is never fully materialised on the main thread just to chart the
    /// selected sub-range — the in-memory `range` filters below still apply.
    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
    }

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

    // MARK: Aggregations

    /// Daily insulin totals split into basal and bolus stacks.
    private var insulinBars: [ChartsInsulinBar] {
        let calendar = Calendar.current
        var basal: [Date: Double] = [:]
        var bolus: [Date: Double] = [:]
        for dose in filteredInsulin {
            let day = calendar.startOfDay(for: dose.timestamp)
            if dose.insulinType.isBasal { basal[day, default: 0] += dose.units }
            else { bolus[day, default: 0] += dose.units }
        }
        var bars: [ChartsInsulinBar] = []
        for (day, units) in bolus where units > 0 {
            bars.append(ChartsInsulinBar(day: day, units: units, category: .bolus))
        }
        for (day, units) in basal where units > 0 {
            bars.append(ChartsInsulinBar(day: day, units: units, category: .basal))
        }
        return bars.sorted { $0.day < $1.day }
    }

    private var carbBars: [ChartsDailyBar] {
        dailyTotals(filteredCarbs.map { ($0.timestamp, $0.grams) })
    }

    private var activityBars: [ChartsDailyBar] {
        dailyTotals(filteredActivity.map { ($0.startTimestamp, Double($0.durationMinutes)) })
    }

    private func dailyTotals(_ items: [(Date, Double)]) -> [ChartsDailyBar] {
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]
        for (date, value) in items {
            totals[calendar.startOfDay(for: date), default: 0] += value
        }
        return totals
            .map { ChartsDailyBar(day: $0.key, total: $0.value) }
            .sorted { $0.day < $1.day }
    }

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

                glucoseSection.appearTransition(delay: 0)
                distributionSection.appearTransition(delay: 0.06)
                insulinSection.appearTransition(delay: 0.12)
                carbsSection.appearTransition(delay: 0.18)
                activitySection.appearTransition(delay: 0.24)
            }
            .padding()
            .animation(.smooth, value: interval)
        }
        .background(Theme.background)
    }

    // MARK: Sections

    private var distribution: [DistributionBin] {
        GlucoseDistribution.bins(activeReadings)
    }

    private var distributionSection: some View {
        SectionCard("Glucose distribution", systemImage: "chart.bar.xaxis") {
            if distribution.isEmpty {
                emptyChart("No glucose readings in this period.")
            } else {
                Chart(distribution) { bin in
                    BarMark(
                        x: .value("Glucose", bin.midpoint),
                        y: .value("Readings", bin.count),
                        width: .fixed(9)
                    )
                    .foregroundStyle(barColor(bin).gradient)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 40)) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let mgdL = value.as(Double.self) {
                                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private func barColor(_ bin: DistributionBin) -> Color {
        switch thresholds.zone(forMgdL: bin.midpoint) {
        case .veryLow, .low: return Theme.zoneWarning
        case .inRange: return Theme.zoneInRange
        case .high, .veryHigh: return Theme.zoneHigh
        }
    }

    private var glucoseSection: some View {
        SectionCard("Glucose trend", systemImage: "waveform.path.ecg") {
            if activeReadings.isEmpty {
                emptyChart("No glucose readings in this period.")
            } else {
                GlucoseTrendChart(readings: activeReadings, thresholds: thresholds, unit: unit)
            }
        }
    }

    private var insulinSection: some View {
        SectionCard("Insulin", systemImage: "syringe.fill") {
            if insulinBars.isEmpty {
                emptyChart("No insulin doses in this period.")
            } else {
                Chart(insulinBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Units", bar.units)
                    )
                    .foregroundStyle(by: .value("Type", bar.category.label))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale([
                    ChartsInsulinBar.Category.bolus.label: Theme.accent,
                    ChartsInsulinBar.Category.basal.label: Theme.zoneWarning,
                ])
                .chartLegend(position: .bottom, spacing: 8)
                .chartXAxis { dateAxis }
                .chartYAxis { unitsAxis(suffix: "U") }
                .frame(height: 200)
                .accessibilityLabel("Daily insulin units, basal and bolus")
            }
        }
    }

    private var carbsSection: some View {
        SectionCard("Carbohydrates", systemImage: "fork.knife") {
            if carbBars.isEmpty {
                emptyChart("No meals logged in this period.")
            } else {
                Chart(carbBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Grams", bar.total)
                    )
                    .foregroundStyle(Theme.zoneHigh.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis { dateAxis }
                .chartYAxis { unitsAxis(suffix: "g") }
                .frame(height: 180)
                .accessibilityLabel("Daily carbohydrate grams")
            }
        }
    }

    private var activitySection: some View {
        SectionCard("Activity", systemImage: "figure.walk") {
            if activityBars.isEmpty {
                emptyChart("No activity logged in this period.")
            } else {
                Chart(activityBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Minutes", bar.total)
                    )
                    .foregroundStyle(Theme.zoneInRange.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis { dateAxis }
                .chartYAxis { unitsAxis(suffix: "min") }
                .frame(height: 180)
                .accessibilityLabel("Daily active minutes")
            }
        }
    }

    // MARK: Shared axis + empty

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
            AxisTick().foregroundStyle(Theme.hairline)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        }
    }

    private func unitsAxis(suffix: String) -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Theme.hairline)
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text("\(number.formatted(.number.precision(.fractionLength(0)))) \(suffix)")
                }
            }
        }
    }

    private func emptyChart(_ message: LocalizedStringKey) -> some View {
        EmptyStateView(
            systemImage: "chart.bar",
            title: "No data",
            message: message
        )
    }
}

// MARK: - Chart aggregation models

/// A single stacked slice of daily insulin (basal or bolus).
private struct ChartsInsulinBar: Identifiable {
    enum Category {
        case basal, bolus
        var label: String { self == .basal ? String(localized: "Basal") : String(localized: "Bolus") }
    }

    let id = UUID()
    let day: Date
    let units: Double
    let category: Category
}

/// A single-value daily bar (carbs grams or activity minutes).
private struct ChartsDailyBar: Identifiable {
    let id = UUID()
    let day: Date
    let total: Double
}

#Preview {
    let env = AppEnvironment.preview()
    return ChartsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
