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
                    SectionCard("Ambulatory Glucose Profile", systemImage: "waveform.path.ecg") {
                        AGPChart(buckets: buckets, thresholds: thresholds, unit: unit)
                        agpLegend
                    }
                    SectionCard("Time in range", systemImage: "chart.bar.fill") {
                        TimeInRangeBar(stats: stats)
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

    private var metrics: some View {
        let pct: (Double) -> String = { ($0 * 100).formatted(.number.precision(.fractionLength(0))) + "%" }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Average", value: GlucoseFormatting.labeled(mgdL: stats.average, unit: unit), systemImage: "number")
            StatTile(title: "Time in range", value: pct(stats.timeInRange), tint: Theme.zoneInRange, systemImage: "target")
            StatTile(title: "GMI (est. A1c)", value: stats.glucoseManagementIndicator.formatted(.number.precision(.fractionLength(1))) + "%", systemImage: "drop.fill")
            StatTile(title: "Variability (CV)", value: pct(stats.coefficientOfVariation), tint: Theme.zoneHigh, systemImage: "waveform.path")
        }
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

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(label)
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
