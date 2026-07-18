import SwiftUI
import SwiftData

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
}

#Preview {
    let env = AppEnvironment.preview()
    return StatisticsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
