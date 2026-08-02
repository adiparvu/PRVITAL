import SwiftUI
import SwiftData
import Charts

/// Two days, one 0–24h axis: pick any two dates and their curves draw over
/// each other — today's accent on top, the comparison day in grey underneath.
/// The fastest way to answer "was Tuesday really worse than Sunday?".
struct DayCompareView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var firstDay = Calendar.current.startOfDay(for: Date())
    @State private var secondDay = Calendar.current.date(
        byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
        ?? Date().addingTimeInterval(-86_400)

    /// (fractional hour, mg/dL) per day, thinned — value pairs, not models.
    @State private var firstPoints: [CompareChartPoint] = []
    @State private var secondPoints: [CompareChartPoint] = []
    @State private var firstStats: PeriodStatistics?
    @State private var secondStats: PeriodStatistics?

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pickers
                    chartCard
                    statsCard
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Compare days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: "\(firstDay.timeIntervalSince1970)|\(secondDay.timeIntervalSince1970)") {
                (firstPoints, firstStats) = load(day: firstDay)
                (secondPoints, secondStats) = load(day: secondDay)
            }
        }
    }

    private var pickers: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Capsule().fill(Theme.accent).frame(width: 14, height: 4)
                DatePicker("First day", selection: $firstDay, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                Spacer()
            }
            HStack(spacing: 8) {
                Capsule().fill(Theme.textTertiary).frame(width: 14, height: 4)
                DatePicker("Second day", selection: $secondDay, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var chartCard: some View {
        SectionCard("Both days, hour by hour", systemImage: "square.stack.3d.up") {
            if firstPoints.isEmpty && secondPoints.isEmpty {
                Text("No glucose readings on either day.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Chart {
                    RectangleMark(
                        xStart: .value("Hour", 0.0), xEnd: .value("Hour", 24.0),
                        yStart: .value("Low", unit.fromMgdL(thresholds.targetLower)),
                        yEnd: .value("High", unit.fromMgdL(thresholds.targetUpper))
                    )
                    .foregroundStyle(Theme.zoneInRange.opacity(0.08))
                    ForEach(secondPoints) { point in
                        LineMark(x: .value("Hour", point.hour),
                                 y: .value("Glucose", unit.fromMgdL(point.mgdL)),
                                 series: .value("Day", "second"))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.textTertiary.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    ForEach(firstPoints) { point in
                        LineMark(x: .value("Hour", point.hour),
                                 y: .value("Glucose", unit.fromMgdL(point.mgdL)),
                                 series: .value("Day", "first"))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
                .chartXScale(domain: 0...24)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
                        AxisValueLabel {
                            if let hour = value.as(Int.self) { Text(verbatim: "\(hour):00") }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Theme.chartPlotBackdrop) }
                .frame(height: 240)
                .accessibilityLabel("Two days of glucose overlaid on the same twenty-four hour axis")
            }
        }
    }

    @ViewBuilder private var statsCard: some View {
        if let firstStats, let secondStats {
            SectionCard("Side by side", systemImage: "chart.bar.xaxis") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        dayHeader(firstDay, tint: Theme.accent)
                        dayHeader(secondDay, tint: Theme.textTertiary)
                    }
                    compareRow(String(localized: "In range"),
                               "\(Int((firstStats.timeInRange * 100).rounded()))%",
                               "\(Int((secondStats.timeInRange * 100).rounded()))%")
                    compareRow(String(localized: "Average"),
                               GlucoseFormatting.string(mgdL: firstStats.average, unit: unit),
                               GlucoseFormatting.string(mgdL: secondStats.average, unit: unit))
                    compareRow(String(localized: "Lows"),
                               "\(firstStats.hypoEvents)", "\(secondStats.hypoEvents)")
                }
            }
        }
    }

    private func dayHeader(_ day: Date, tint: Color) -> some View {
        Text(day, format: .dateTime.day().month(.abbreviated))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private func compareRow(_ title: String, _ first: String, _ second: String) -> some View {
        GridRow {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text(first).font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary).monospacedDigit()
            Text(second).font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary).monospacedDigit()
        }
    }

    /// One bounded fetch per day — ~288 CGM rows, thinned to ≤96 points.
    private func load(day: Date) -> ([CompareChartPoint], PeriodStatistics?) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        guard !readings.isEmpty else { return ([], nil) }
        let thinned = GlucoseDownsampler.downsample(readings, maxPoints: 96)
        let points = thinned.enumerated().map { index, reading in
            CompareChartPoint(id: index,
                              hour: reading.timestamp.timeIntervalSince(start) / 3600,
                              mgdL: reading.valueMgdL)
        }
        return (points, StatisticsEngine.glucose(readings, thresholds: thresholds))
    }
}

struct CompareChartPoint: Identifiable {
    let id: Int
    let hour: Double
    let mgdL: Double
}
