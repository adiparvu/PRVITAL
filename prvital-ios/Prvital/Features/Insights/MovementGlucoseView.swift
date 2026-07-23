import SwiftUI
import SwiftData
import Charts

/// "Movement & glucose": one day's glucose and heart rate on a shared time axis,
/// with activity sessions shaded across both charts — so you can see how a
/// workout moved your heart rate and your glucose together. Heart rate is read
/// from Apple Health (read-only); it needs the Apple Health source connected.
struct MovementGlucoseView: View {
    @Environment(AppEnvironment.self) private var env

    let date: Date

    @Query private var glucose: [GlucoseReading]
    @Query private var activity: [ActivityEntry]

    @State private var heartRate: [HeartRateSample] = []
    @State private var loadingHR = true

    init(date: Date) {
        self.date = date
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> {
            $0.timestamp >= dayStart && $0.timestamp < dayEnd
        }, sort: \.timestamp)
        _activity = Query(filter: #Predicate<ActivityEntry> {
            $0.startTimestamp >= dayStart && $0.startTimestamp < dayEnd
        }, sort: \.startTimestamp)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var dayStart: Date { Calendar.current.startOfDay(for: date) }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
    }
    private var xDomain: ClosedRange<Date> { dayStart...dayEnd }
    private var readings: [GlucoseReading] { glucose.filter(\.isActive) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                combinedCard
                impactCard
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Movement & glucose")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: date) { await loadHeartRate() }
    }

    // MARK: Cards

    /// Glucose and heart rate overlaid on one shared time axis — glucose in the
    /// app tint on the left mg/dL scale, heart rate in red on the right bpm scale
    /// — so a workout's effect on both is visible at a glance. Swift Charts has a
    /// single y-domain per chart, so heart rate is mapped into the glucose value
    /// range (`hrScale`) and the trailing axis relabels the ticks back to bpm.
    private var combinedCard: some View {
        SectionCard("Glucose & heart rate", systemImage: "heart.text.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if loadingHR && readings.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 160)
                } else if readings.isEmpty && heartRate.isEmpty {
                    emptyRow("No glucose or heart-rate data on this day.")
                } else {
                    Chart {
                        activityBands
                        RuleMark(y: .value("High", thresholds.targetUpper))
                            .foregroundStyle(Theme.zoneHigh.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value("Low", thresholds.targetLower))
                            .foregroundStyle(Theme.zoneWarning.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        // Glucose — real mg/dL on the left scale.
                        ForEach(GlucoseDownsampler.downsample(readings, maxPoints: 300)) { r in
                            LineMark(x: .value("Time", r.timestamp),
                                     y: .value("Glucose", r.valueMgdL),
                                     series: .value("Series", "Glucose"))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                        // Heart rate — bpm mapped into the glucose domain (red).
                        ForEach(downsampledHR) { s in
                            LineMark(x: .value("Time", s.timestamp),
                                     y: .value("Heart rate", s.bpm * hrScale),
                                     series: .value("Series", "Heart rate"))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.zoneCritical)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: 0...gTop)
                    .chartXAxis { hourAxis }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.6))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        AxisMarks(position: .trailing, values: hrAxisPlottedValues) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int((v / hrScale).rounded()))").foregroundStyle(Theme.zoneCritical)
                                }
                            }
                        }
                    }
                    .frame(height: 240)
                    .accessibilityLabel("Glucose in milligrams per deciliter and heart rate in beats per minute across the day")

                    HStack(spacing: 16) {
                        legendItem(color: Theme.accent, label: String(localized: "Glucose"), unit: unit.rawValue)
                        legendItem(color: Theme.zoneCritical, label: String(localized: "Heart rate"), unit: "bpm")
                        Spacer()
                    }

                    if heartRate.isEmpty && !loadingHR {
                        Text("No heart-rate data from Apple Health for this day. Connect Apple Health in Sources to see it here.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func legendItem(color: Color, label: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text("\(label) (\(unit))")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // Shared y-scale plumbing for the dual-axis chart.

    /// Top of the glucose (left) axis — at least 300, rounded above the day's max.
    private var gTop: Double {
        let maxG = readings.map(\.valueMgdL).max() ?? 0
        return max(300, (maxG / 50).rounded(.up) * 50)
    }
    /// Top of the heart-rate (right) axis — at least 160, rounded above the max.
    private var hrTop: Double {
        let maxHR = heartRate.map(\.bpm).max() ?? 0
        return max(160, (maxHR / 20).rounded(.up) * 20)
    }
    /// Factor mapping bpm into the glucose y-domain so both series share one scale.
    private var hrScale: Double { gTop / hrTop }
    /// Trailing-axis tick positions (in the plotted glucose domain) for ~5 evenly
    /// spaced bpm gridlines; the axis relabels each back to bpm.
    private var hrAxisPlottedValues: [Double] {
        stride(from: 0, through: hrTop, by: max(hrTop / 4, 1)).map { $0 * hrScale }
    }

    @ViewBuilder private var impactCard: some View {
        if !activity.isEmpty {
            SectionCard("Movement", systemImage: "figure.walk") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(activity) { session in
                        HStack {
                            Image(systemName: "figure.run").foregroundStyle(Theme.accent)
                            Text(session.activityType.label)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(session.durationMinutes) min")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    /// Activity sessions shaded as full-height vertical bands, shared by both charts.
    private var activityBands: some ChartContent {
        ForEach(activity) { session in
            RectangleMark(
                xStart: .value("Start", session.startTimestamp),
                xEnd: .value("End", session.endTimestamp ?? session.startTimestamp.addingTimeInterval(TimeInterval(session.durationSeconds)))
            )
            .foregroundStyle(Theme.accent.opacity(0.12))
        }
    }

    private var hourAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
            AxisValueLabel(format: .dateTime.hour())
        }
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var downsampledHR: [HeartRateSample] {
        guard heartRate.count > 400 else { return heartRate }
        let stride = heartRate.count / 400 + 1
        return heartRate.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }

    private func loadHeartRate() async {
        loadingHR = true
        defer { loadingHR = false }
        heartRate = (try? await env.healthKit.fetchHeartRateSamples(from: dayStart, to: dayEnd)) ?? []
    }
}
