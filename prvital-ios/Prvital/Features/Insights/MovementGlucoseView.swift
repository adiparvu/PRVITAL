import SwiftUI
import SwiftData
import Charts

/// "Movement & glucose": glucose and heart rate on one shared time axis, with
/// activity sessions shaded across both — so you can see how movement moved your
/// heart rate and your glucose together. Heart rate is read from Apple Health
/// (read-only); it needs the Apple Health source connected.
///
/// The window follows the same Day/Week/Month/Year vocabulary as the rest of
/// Insights, and the screen carries its own picker because it is pushed onto the
/// stack, away from the shared top-left menu. It used to be pinned to a single
/// hard-coded day, which is why the period selection appeared to do nothing here.
///
/// Everything heavy runs on `MovementBuilder` (a background ModelActor) and, for
/// heart rate, on a HealthKit statistics collection query — a Year window is
/// ~100k CGM rows and vastly more beats, and neither ever reaches the main
/// thread as raw samples.
struct MovementGlucoseView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seeded from the period Insights was showing, then owned by this screen's
    /// own picker.
    @State private var interval: InsightsInterval
    @State private var derived = MovementPayload()
    @State private var ready = false
    @State private var heartRate: [HeartRateBucket] = []
    @State private var loadingHR = true
    /// The actual last beat Apple Health holds, for the "Now" readout. Kept
    /// separate from `heartRate` on purpose — see `liveHeartRate`.
    @State private var latestHeartRate: HeartRateSample?
    /// Drives the one-shot rise of both series whenever the window changes, so
    /// switching period is a movement rather than a swap.
    @State private var reveal: Double = 0

    init(interval: InsightsInterval) {
        _interval = State(initialValue: interval)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var range: ClosedRange<Date> { interval.dateRange(now: windowEnd) }
    /// Pinned per build so the chart's x-domain, the fetch and the heart-rate
    /// query all describe exactly the same window.
    @State private var windowEnd = Date()

    /// Re-derives when the period changes or new data lands (`dataVersion` bumps
    /// on every write and every completed CGM sync — which is what makes the
    /// chart grow by itself while the screen is open).
    private struct BuildKey: Equatable {
        let interval: InsightsInterval
        let dataVersion: Int
    }

    private var buildKey: BuildKey {
        BuildKey(interval: interval, dataVersion: env.dataVersion)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                periodPicker
                liveStrip
                combinedCard
                movementCard
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Movement & glucose")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: buildKey) {
            let end = Date()
            windowEnd = end
            let builder = MovementBuilder(modelContainer: env.modelContainer)
            let payload = await builder.build(
                range: interval.dateRange(now: end), bucketSeconds: bucketSeconds)
            derived = payload
            ready = true
        }
        // Keyed on the SAME key as the glucose build, so the pulse history grows
        // alongside it instead of being frozen at whatever was there when the
        // screen opened. Only the first load shows a spinner.
        .task(id: buildKey) {
            loadingHR = heartRate.isEmpty
            let window = interval.dateRange(now: Date())
            heartRate = await env.healthKit.heartRateBuckets(
                from: window.lowerBound, to: window.upperBound, every: heartRateBucket)
            loadingHR = false
        }
        // The "Now" beat, polled on its own cadence. Heart rate arrives from the
        // Watch on its own schedule, unrelated to CGM readings, so it can't ride
        // the glucose key.
        .task {
            while !Task.isCancelled {
                latestHeartRate = await env.healthKit.latestHeartRate()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: interval) { _, _ in
            Haptics.play(.selection)
            reveal = 0
        }
    }

    /// Replays the rise. Reduce Motion gets the finished chart immediately.
    private func rise() {
        guard !reduceMotion else { reveal = 1; return }
        withAnimation(.smooth(duration: 0.7)) { reveal = 1 }
    }

    // MARK: Window shape

    /// How wide one aggregation bucket is. A Day plots individual readings; past
    /// that, a whole month of raw CGM is an unreadable thicket, so each point
    /// becomes an average with its spread shaded behind it.
    private var bucketSeconds: Double {
        switch interval {
        case .day:   return 0
        case .week:  return 3600           // hourly
        case .month: return 6 * 3600       // four points a day
        case .year:  return 24 * 3600      // daily
        }
    }

    /// The matching HealthKit bucket. Heart rate is far denser than CGM, so a
    /// Day gets quarter-hour buckets rather than raw beats.
    private var heartRateBucket: DateComponents {
        switch interval {
        case .day:   return DateComponents(minute: 15)
        case .week:  return DateComponents(hour: 1)
        case .month: return DateComponents(hour: 6)
        case .year:  return DateComponents(day: 1)
        }
    }

    // MARK: Header

    private var periodPicker: some View {
        Picker("Period", selection: $interval) {
            ForEach(InsightsInterval.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Period")
    }

    /// The live readout: the newest glucose with a breathing ring, its age
    /// counting up on its own, and the latest heart rate under a beating heart.
    /// This is the part of the screen that keeps moving while you watch it.
    @ViewBuilder private var liveStrip: some View {
        if let date = derived.latestDate, let mgdL = derived.latestMgdL {
            let zone = thresholds.zone(forMgdL: mgdL).color
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(zone).frame(width: 10, height: 10)
                    PulsingLiveDot(color: zone)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(zone)
                            .contentTransition(.numericText())
                        Text(unit.rawValue)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    // Ticks up by itself — no timer, no re-render of the charts.
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if let sample = latestHeartRate {
                    let fresh = Date().timeIntervalSince(sample.timestamp) <= Self.heartRateFreshness
                    HStack(spacing: 6) {
                        BeatingHeart(beating: fresh)
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(Int(sample.bpm.rounded()))")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(fresh ? Theme.textPrimary : Theme.textTertiary)
                                    .contentTransition(.numericText())
                                Text("bpm")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            // Its real age, exactly like the glucose beside it —
                            // so a beat from two hours ago can never pass for now.
                            Text(sample.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Latest heart rate \(Int(sample.bpm.rounded())) beats per minute")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .animation(.smooth, value: mgdL)
        }
    }

    /// Past this age a sample stops being dressed up as the current beat: the
    /// heart stops beating, the number greys out, and the age reads for itself.
    private static let heartRateFreshness: TimeInterval = 15 * 60

    // MARK: Chart

    /// Glucose and heart rate overlaid on one shared time axis — glucose in the
    /// app tint on the left mg/dL scale, heart rate in red on the right bpm scale
    /// — so movement's effect on both is visible at a glance. Swift Charts has a
    /// single y-domain per chart, so heart rate is mapped into the glucose value
    /// range (`hrScale`) and the trailing axis relabels the ticks back to bpm.
    private var combinedCard: some View {
        SectionCard("Glucose & heart rate", systemImage: "heart.text.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if !ready || (loadingHR && derived.points.isEmpty) {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 240)
                } else if derived.points.isEmpty && heartRate.isEmpty {
                    emptyRow("No glucose or heart-rate data in this period.")
                } else {
                    chart
                    legend
                    caption
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            activityBands
            RuleMark(y: .value("High", thresholds.targetUpper))
                .foregroundStyle(Theme.zoneHigh.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Low", thresholds.targetLower))
                .foregroundStyle(Theme.zoneWarning.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // The bucket spread, so an averaged line still shows how far the day
            // actually swung. Absent on Day, where the points are real readings.
            if !derived.isRaw {
                ForEach(derived.points) { point in
                    // `series:` is not optional here: without it Swift Charts
                    // folds both bands into one implicit series and joins the
                    // glucose spread to the heart-rate spread.
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Lowest", point.low * reveal),
                             yEnd: .value("Highest", point.high * reveal),
                             series: .value("Band", "Glucose"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent.opacity(0.14))
                }
            }
            // Glucose — real mg/dL on the left scale.
            ForEach(derived.points) { point in
                LineMark(x: .value("Time", point.date),
                         y: .value("Glucose", point.mgdL * reveal),
                         series: .value("Series", "Glucose"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            // Heart rate — bpm mapped into the glucose domain (red).
            if hasHeartRateSpread {
                ForEach(heartRate) { bucket in
                    AreaMark(x: .value("Time", bucket.start),
                             yStart: .value("Lowest", bucket.minimum * hrScale * reveal),
                             yEnd: .value("Highest", bucket.maximum * hrScale * reveal),
                             series: .value("Band", "Heart rate"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.zoneCritical.opacity(0.12))
                }
            }
            ForEach(heartRate) { bucket in
                LineMark(x: .value("Time", bucket.start),
                         y: .value("Heart rate", bucket.average * hrScale * reveal),
                         series: .value("Series", "Heart rate"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.zoneCritical)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: 0...gTop)
        .chartXAxis { timeAxis }
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
        .chartPlotStyle { plot in
            // Flat card fills don't blur the wallpaper, so the plot gets its own
            // backdrop — otherwise a bright photo swallows the thin lines.
            plot.background(Theme.chartPlotBackdrop)
        }
        // The one-shot rise, plus a glide whenever the ceiling jumps a tier.
        // Driven from a `.task` on the chart itself (like the distribution
        // histogram) so the change lands AFTER the chart is on screen — a value
        // that moves in the same update that inserts the view is not animated.
        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: reveal)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: gTop)
        .task(id: interval) { rise() }
        // A live, pulsing ring on the newest reading — a soft ping that keeps
        // expanding and fading, so the chart visibly breathes. A real SwiftUI
        // overlay rather than a chart symbol, so the animation actually runs.
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let date = derived.latestDate, let mgdL = derived.latestMgdL,
                   let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: date),
                   let y = proxy.position(forY: mgdL) {
                    let rect = geo[plotFrame]
                    ZStack {
                        Circle()
                            .fill(thresholds.zone(forMgdL: mgdL).color)
                            .frame(width: 7, height: 7)
                        PulsingLiveDot(color: thresholds.zone(forMgdL: mgdL).color)
                    }
                    .position(x: rect.minX + x, y: rect.minY + y)
                    .opacity(reveal)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 240)
        .accessibilityLabel("Glucose in milligrams per deciliter and heart rate in beats per minute across \(interval.periodLabel)")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Theme.accent, label: String(localized: "Glucose"), unit: unit.rawValue)
            legendItem(color: Theme.zoneCritical, label: String(localized: "Heart rate"), unit: "bpm")
            Spacer()
        }
    }

    @ViewBuilder private var caption: some View {
        if heartRate.isEmpty && !loadingHR {
            Text("No heart-rate data from Apple Health for this period. Connect Apple Health in Sources to see it here.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !derived.isRaw {
            Text("Each point is an average for its slice of time; the shaded band is the range it covered.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Top of the glucose (left) axis — at least 300, rounded above the window's max.
    private var gTop: Double {
        let maxG = derived.points.map(\.high).max() ?? 0
        return max(300, (maxG / 50).rounded(.up) * 50)
    }
    /// Top of the heart-rate (right) axis — at least 160, rounded above the max.
    private var hrTop: Double {
        let maxHR = heartRate.map(\.maximum).max() ?? 0
        return max(160, (maxHR / 20).rounded(.up) * 20)
    }
    /// Factor mapping bpm into the glucose y-domain so both series share one scale.
    private var hrScale: Double { gTop / hrTop }
    /// Trailing-axis tick positions (in the plotted glucose domain) for ~5 evenly
    /// spaced bpm gridlines; the axis relabels each back to bpm.
    private var hrAxisPlottedValues: [Double] {
        stride(from: 0, through: hrTop, by: max(hrTop / 4, 1)).map { $0 * hrScale }
    }
    /// Only band the heart rate when the buckets actually cover a spread —
    /// otherwise the band is a hairline drawn under the line for nothing.
    private var hasHeartRateSpread: Bool {
        heartRate.contains { $0.maximum - $0.minimum > 1 }
    }

    // MARK: Movement

    @ViewBuilder private var movementCard: some View {
        if derived.sessionCount > 0 {
            SectionCard("Movement", systemImage: "figure.walk") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        summaryColumn(value: "\(derived.sessionCount)", label: "Sessions")
                        Divider().frame(height: 30).overlay(Theme.hairline)
                        summaryColumn(value: durationText(derived.totalMinutes), label: "Active time")
                        if let impact = derived.impact {
                            Divider().frame(height: 30).overlay(Theme.hairline)
                            summaryColumn(
                                value: GlucoseFormatting.string(
                                    mgdL: abs(impact.averageChangeMgdL), unit: unit),
                                label: impact.averageChangeMgdL <= 0
                                    ? "Typical drop" : "Typical rise")
                        }
                    }

                    // Which sport moves glucose how much — the reason to open
                    // this screen at all once the chart is familiar.
                    if !derived.typeImpacts.isEmpty {
                        Divider().overlay(Theme.hairline)
                        ForEach(derived.typeImpacts) { impact in
                            HStack {
                                Text(ActivityType(rawValue: impact.typeRaw)?.label
                                     ?? ActivityType.walking.label)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("×\(impact.sessions)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Text(deltaText(impact.averageChangeMgdL))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(impact.averageChangeMgdL <= 0
                                                     ? Theme.zoneInRange : Theme.zoneHigh)
                            }
                        }
                    }

                    Divider().overlay(Theme.hairline)

                    ForEach(derived.recentSessions) { session in
                        HStack {
                            Image(systemName: "figure.run").foregroundStyle(Theme.accent)
                            Text(ActivityType(rawValue: session.typeRaw)?.label
                                 ?? ActivityType.walking.label)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(session.start, format: sessionDateFormat)
                                .foregroundStyle(Theme.textTertiary)
                            Text("\(session.minutes) min")
                                .foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }

                    if derived.sessionCount > derived.recentSessions.count {
                        Text("+\(derived.sessionCount - derived.recentSessions.count) more")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private func summaryColumn(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "−18 mg/dL" / "+6 mg/dL" in the user's display unit, sign always shown.
    private func deltaText(_ deltaMgdL: Double) -> String {
        let magnitude = GlucoseFormatting.string(mgdL: abs(deltaMgdL), unit: unit)
        return (deltaMgdL <= 0 ? "−" : "+") + magnitude
    }

    private func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Sessions on a Day window are placed by clock time; longer windows need
    /// the date to tell them apart.
    private var sessionDateFormat: Date.FormatStyle {
        interval == .day
            ? .dateTime.hour().minute()
            : .dateTime.month(.abbreviated).day().hour().minute()
    }

    /// Activity sessions shaded as full-height vertical bands, behind both series.
    /// Very short sessions are widened to a minimum slice of the window, so a
    /// 20-minute walk is still visible inside a year.
    private var activityBands: some ChartContent {
        let minimumSpan = range.upperBound.timeIntervalSince(range.lowerBound) / 400
        return ForEach(derived.bands) { session in
            RectangleMark(
                xStart: .value("Start", session.start),
                xEnd: .value("End", max(session.end, session.start.addingTimeInterval(minimumSpan)))
            )
            .foregroundStyle(Theme.accent.opacity(0.12))
        }
    }

    // MARK: Axis + empty

    /// Whole-unit ticks whose stride follows the window, so labels never repeat.
    private var timeAxis: some AxisContent {
        AxisMarks(values: axisValues) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
            AxisValueLabel(format: axisFormat)
        }
    }

    private var axisValues: AxisMarkValues {
        switch interval {
        case .day:   return .stride(by: .hour, count: 6)
        case .week:  return .stride(by: .day, count: 1)
        case .month: return .stride(by: .day, count: 7)
        case .year:  return .stride(by: .month, count: 2)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch interval {
        case .day:   return .dateTime.hour()
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).day()
        case .year:  return .dateTime.month(.abbreviated)
        }
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// A heart that beats — the live tell beside the current bpm. It only beats
/// when the reading really is current; a stale one sits still and dimmed, so the
/// animation itself never claims something the data doesn't support.
private struct BeatingHeart: View {
    var beating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.subheadline)
            .foregroundStyle(beating ? Theme.zoneCritical : Theme.textTertiary)
            .scaleEffect(animating ? 1.16 : 0.90)
            .onAppear { start() }
            .onChange(of: beating) { _, _ in start() }
            .accessibilityHidden(true)
    }

    private func start() {
        guard beating, !reduceMotion else {
            withAnimation(.smooth) { animating = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            animating = true
        }
    }
}
