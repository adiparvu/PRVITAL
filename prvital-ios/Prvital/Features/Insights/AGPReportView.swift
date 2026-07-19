import SwiftUI
import SwiftData
import Charts

/// Ambulatory Glucose Profile — the standard clinical report: key metrics, the
/// percentile "modal day" curve (median + IQR + 10/90 lines over 24 hours), and
/// the Time-in-Range bar.
struct AGPReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var readings: [GlucoseReading]

    @State private var interval: InsightsInterval = .month

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var windowReadings: [GlucoseReading] {
        let range = interval.dateRange()
        return readings.filter { $0.isActive && range.contains($0.timestamp) }
    }
    private var stats: PeriodStatistics {
        StatisticsEngine.glucose(windowReadings, thresholds: thresholds)
    }
    private var buckets: [AGPBucket] {
        AGPAggregator.buckets(windowReadings, binMinutes: 60)
    }
    private var patterns: [GlucoseInsight] {
        GlucosePatternDetector.insights(windowReadings, thresholds: thresholds)
    }
    private var previousWindowReadings: [GlucoseReading] {
        let range = interval.previousDateRange()
        return readings.filter { $0.isActive && range.contains($0.timestamp) }
    }
    private var comparison: StatComparison {
        let previous = previousWindowReadings.isEmpty
            ? nil
            : StatisticsEngine.glucose(previousWindowReadings, thresholds: thresholds)
        return StatComparator.compare(current: stats, previous: previous)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Interval", selection: $interval) {
                    ForEach(InsightsInterval.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: interval) { _, _ in Haptics.play(.selection) }

                if stats.hasGlucose {
                    metrics
                    if comparison.hasPrevious {
                        comparisonCard(comparison)
                    }
                    SectionCard("Ambulatory Glucose Profile", systemImage: "waveform.path.ecg") {
                        AGPChart(buckets: buckets, thresholds: thresholds, unit: unit)
                        agpLegend
                    }
                    SectionCard("Time in range", systemImage: "chart.bar.fill") {
                        TimeInRangeBar(stats: stats)
                    }
                    if !patterns.isEmpty {
                        SectionCard("Patterns", systemImage: "sparkles") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(patterns) { insight in
                                    patternRow(insight)
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateView(systemImage: "waveform.path.ecg",
                                   title: "Not enough data",
                                   message: "Log or sync more glucose to build your profile.")
                }
            }
            .padding()
        }
        .background(Theme.background)
    }

    private var coverage: Double {
        let range = interval.dateRange()
        let window = range.upperBound.timeIntervalSince(range.lowerBound)
        return GlucoseCoverage.coverage(readingCount: windowReadings.count, window: window)
    }

    private var metrics: some View {
        let pct: (Double) -> String = { ($0 * 100).formatted(.number.precision(.fractionLength(0))) + "%" }
        return VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Average", value: GlucoseFormatting.labeled(mgdL: stats.average, unit: unit), systemImage: "number")
                StatTile(title: "Time in range", value: pct(stats.timeInRange), tint: Theme.zoneInRange, systemImage: "target")
                StatTile(title: "GMI (est. A1c)", value: stats.glucoseManagementIndicator.formatted(.number.precision(.fractionLength(1))) + "%", systemImage: "drop.fill")
                StatTile(title: "Variability (CV)", value: pct(stats.coefficientOfVariation), tint: Theme.zoneHigh, systemImage: "waveform.path")
                StatTile(title: "Data coverage", value: pct(coverage),
                         tint: GlucoseCoverage.isReliable(coverage) ? Theme.zoneInRange : Theme.zoneWarning,
                         systemImage: "sensor.tag.radiowaves.forward")
            }
            if !GlucoseCoverage.isReliable(coverage) {
                Label("Data coverage is below 70%, so the estimated A1c (GMI) is less reliable for this period.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Period comparison

    private func comparisonCard(_ comparison: StatComparison) -> some View {
        let tirDelta = comparison.timeInRangeDelta
        let tirText = (tirDelta * 100).formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%"
        let tirTint = tirDelta > 0 ? Theme.zoneInRange : (tirDelta < 0 ? Theme.zoneCritical : Theme.textSecondary)
        let tirSymbol = tirDelta > 0 ? "arrow.up.right" : (tirDelta < 0 ? "arrow.down.right" : "arrow.right")

        let avgDelta = unit.fromMgdL(comparison.averageDelta)
        let avgText = avgDelta.formatted(.number.precision(.fractionLength(unit.fractionDigits)).sign(strategy: .always())) + " " + unit.rawValue

        return SectionCard("Compared with previous period", systemImage: "arrow.left.arrow.right") {
            HStack(spacing: 20) {
                deltaMetric(title: "Time in range", value: tirText, symbol: tirSymbol, tint: tirTint)
                Divider().frame(height: 38).overlay(Theme.hairline)
                deltaMetric(title: "Average", value: avgText, symbol: "arrow.left.arrow.right", tint: Theme.textSecondary)
                Spacer()
            }
        }
    }

    private func deltaMetric(title: LocalizedStringKey, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(value, systemImage: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var agpLegend: some View {
        HStack(spacing: 14) {
            legendSwatch(Theme.accent, "Median")
            legendSwatch(Theme.accent.opacity(0.18), "25–75%")
            legendSwatch(Theme.textTertiary, "10 / 90%")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
    }

    private func legendSwatch(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(label)
        }
    }

    // MARK: Patterns

    private func patternRow(_ insight: GlucoseInsight) -> some View {
        let pct = insight.fraction.formatted(.percent.precision(.fractionLength(0)))
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.symbol)
                .foregroundStyle(insight.kind == .frequentLow ? Theme.zoneCritical : Theme.zoneHigh)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    periodText(insight.period)
                    Text("·").foregroundStyle(Theme.textTertiary)
                    kindText(insight.kind)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                detailText(insight, pct: pct)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func periodText(_ period: DayPeriod) -> Text {
        switch period {
        case .overnight: return Text("Overnight")
        case .morning: return Text("Morning")
        case .afternoon: return Text("Afternoon")
        case .evening: return Text("Evening")
        }
    }

    private func kindText(_ kind: GlucoseInsight.Kind) -> Text {
        switch kind {
        case .frequentLow: return Text("frequent lows")
        case .frequentHigh: return Text("frequent highs")
        }
    }

    private func detailText(_ insight: GlucoseInsight, pct: String) -> Text {
        switch insight.kind {
        case .frequentLow: return Text("\(pct) below range")
        case .frequentHigh: return Text("\(pct) above range")
        }
    }
}

/// The AGP percentile curve over a 24-hour day.
private struct AGPChart: View {
    let buckets: [AGPBucket]
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit

    private var yDomain: ClosedRange<Double> {
        let hi = max(buckets.map(\.p90).max() ?? thresholds.high, thresholds.high) + 20
        return 0...max(hi, 250)
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Upper target", thresholds.targetUpper))
                .foregroundStyle(Theme.zoneInRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Lower target", thresholds.targetLower))
                .foregroundStyle(Theme.zoneInRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(buckets) { b in
                AreaMark(x: .value("Time", b.minutesOfDay),
                         yStart: .value("p25", b.p25), yEnd: .value("p75", b.p75))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent.opacity(0.18))
            }
            ForEach(buckets) { b in
                LineMark(x: .value("Time", b.minutesOfDay), y: .value("p10", b.p10),
                         series: .value("s", "p10"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(buckets) { b in
                LineMark(x: .value("Time", b.minutesOfDay), y: .value("p90", b.p90),
                         series: .value("s", "p90"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(buckets) { b in
                LineMark(x: .value("Time", b.minutesOfDay), y: .value("Median", b.p50),
                         series: .value("s", "median"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...1440)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 1440, by: 360))) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let minutes = value.as(Int.self) { Text("\(minutes / 60):00") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let mgdL = value.as(Double.self) { Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit)) }
                }
            }
        }
        .frame(height: 240)
    }
}

/// The five-band Time-in-Range bar (very low / low / in range / high / very high).
private struct TimeInRangeBar: View {
    let stats: PeriodStatistics

    private var bands: [(color: Color, fraction: Double, label: String)] {
        let low = max(stats.timeBelowRange - stats.timeVeryLow, 0)
        let high = max(stats.timeAboveRange - stats.timeVeryHigh, 0)
        return [
            (Theme.zoneCritical, stats.timeVeryLow, "Very low"),
            (Theme.zoneWarning, low, "Low"),
            (Theme.zoneInRange, stats.timeInRange, "In range"),
            (Theme.zoneHigh, high, "High"),
            (Theme.zoneWarning, stats.timeVeryHigh, "Very high"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                        band.color
                            .frame(width: max(geo.size.width * band.fraction, band.fraction > 0 ? 2 : 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)

            HStack {
                label("In range", stats.timeInRange, Theme.zoneInRange)
                Spacer()
                label("Below", stats.timeBelowRange, Theme.zoneWarning)
                Spacer()
                label("Above", stats.timeAboveRange, Theme.zoneHigh)
            }
        }
    }

    private func label(_ text: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(((fraction * 100).formatted(.number.precision(.fractionLength(0)))) + "%")
                .font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AGPReportView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
