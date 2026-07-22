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
                glucoseCard
                heartRateCard
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

    private var glucoseCard: some View {
        SectionCard("Glucose", systemImage: "drop.fill") {
            if readings.isEmpty {
                emptyRow("No glucose readings on this day.")
            } else {
                Chart {
                    activityBands
                    RuleMark(y: .value("High", thresholds.targetUpper))
                        .foregroundStyle(Theme.zoneHigh.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("Low", thresholds.targetLower))
                        .foregroundStyle(Theme.zoneWarning.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(GlucoseDownsampler.downsample(readings, maxPoints: 300)) { r in
                        LineMark(x: .value("Time", r.timestamp), y: .value("Glucose", r.valueMgdL))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis { hourAxis }
                .frame(height: 180)
            }
        }
    }

    private var heartRateCard: some View {
        SectionCard("Heart rate", systemImage: "heart.fill") {
            if loadingHR {
                ProgressView().frame(maxWidth: .infinity).frame(height: 120)
            } else if heartRate.isEmpty {
                emptyRow("No heart-rate data from Apple Health for this day. Connect Apple Health in Sources to see it here.")
            } else {
                Chart {
                    activityBands
                    ForEach(downsampledHR) { s in
                        LineMark(x: .value("Time", s.timestamp), y: .value("BPM", s.bpm))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.zoneHigh)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis { hourAxis }
                .frame(height: 180)
                .accessibilityLabel("Heart rate in beats per minute across the day")
            }
        }
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
