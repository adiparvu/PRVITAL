import SwiftUI
import Charts

/// The dashboard hero: a circular gauge showing the current glucose value,
/// tinted by its zone, with the trend arrow beneath.
struct GlucoseGaugeRing: View {
    let mgdL: Double
    let zone: GlucoseZone
    let unit: GlucoseUnit
    var trend: GlucoseTrend?
    var diameter: CGFloat = 200

    /// Display scale for the ring sweep (clamped).
    private let scaleLow = 40.0
    private let scaleHigh = 320.0

    @State private var pulse = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        min(max((mgdL - scaleLow) / (scaleHigh - scaleLow), 0), 1)
    }

    var body: some View {
        ZStack {
            // Soft glow that breathes behind the ring, tinted by the zone.
            Circle()
                .stroke(zone.color.opacity(0.35), lineWidth: 14)
                .blur(radius: 11)
                .scaleEffect(pulse ? 1.05 : 0.97)
                .opacity(pulse ? 0.8 : 0.4)

            Circle()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Circle()
                .trim(from: 0, to: appeared ? fraction : 0)
                .stroke(zone.color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)

            VStack(spacing: 2) {
                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit.rawValue).font(.subheadline).foregroundStyle(Theme.textSecondary)
                if let trend {
                    TrendBadge(trend: trend, showsLabel: true).padding(.top, 2)
                }
            }
            .scaleEffect(appeared ? 1 : 0.9)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            // The perpetual "breathing" glow is decorative — skip it under Reduce
            // Motion, leaving a calm static glow; the one-shot appear still plays.
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Glucose \(GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)), \(zone.label)"
                            + (trend.map { ", \($0.label)" } ?? ""))
    }
}

/// A line chart of glucose over time with the target range shaded, built on
/// Swift Charts. Values are plotted in mg/dL and formatted to the display unit.
///
/// The full-size variant is styled like a tide chart: the y-axis is hidden and
/// the numbers live on the curve instead — peaks and valleys are marked with a
/// dot plus a small value-and-time label (above crests, below troughs), and the
/// latest reading is a background-filled dot ringed in its zone's colour. It
/// also fills the curve with a gradient, lets you scrub with a finger to read
/// any point, and fades in on appear. The compact variant keeps a tiny y-axis
/// and a simple dot, with no annotations.
struct GlucoseTrendChart: View {
    let readings: [GlucoseReading]
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit
    var compact = false

    @State private var selectedDate: Date?
    @State private var appeared = false

    private var sorted: [GlucoseReading] {
        readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }
    }

    /// Whether scrubbing / detailed marks are enabled (full-size only).
    private var interactive: Bool { !compact }

    private var selectedReading: GlucoseReading? {
        guard interactive, let selectedDate, !sorted.isEmpty else { return nil }
        return sorted.min {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        }
    }

    /// Tide-chart-style callouts: the window's high and low plus up to two
    /// other prominent local extremes, labeled directly on the curve. Skipped
    /// for compact charts and for windows too small to have meaningful shape.
    private var extremes: [ChartExtreme] {
        guard interactive, sorted.count >= 5,
              let first = sorted.first?.timestamp, let last = sorted.last?.timestamp
        else { return [] }
        // Labels need horizontal room proportional to the window: keep the
        // annotated extremes at least an eighth of the window apart, and never
        // closer than 45 minutes.
        let separation = max(45 * 60, last.timeIntervalSince(first) / 8)
        return ChartExtremes.find(
            in: sorted.map { (date: $0.timestamp, value: $0.valueMgdL) },
            minimumSeparation: separation
        )
    }

    private func zoneColor(_ mgdL: Double) -> Color {
        thresholds.zone(forMgdL: mgdL).color
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// A spoken summary of the trend for VoiceOver, since the chart marks alone
    /// convey nothing to a non-visual reader.
    private var accessibilitySummary: String {
        guard let latest = sorted.last else {
            return String(localized: "Glucose trend chart, no readings yet")
        }
        let values = sorted.map(\.valueMgdL)
        let average = values.reduce(0, +) / Double(values.count)
        let latestText = GlucoseFormatting.labeled(mgdL: latest.valueMgdL, unit: unit)
        let averageText = GlucoseFormatting.labeled(mgdL: average, unit: unit)
        let lowText = GlucoseFormatting.labeled(mgdL: values.min() ?? 0, unit: unit)
        let highText = GlucoseFormatting.labeled(mgdL: values.max() ?? 0, unit: unit)
        return String(localized: "Glucose trend over \(sorted.count) readings. Latest \(latestText), average \(averageText), low \(lowText), high \(highText).")
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Target upper", thresholds.targetUpper))
                .foregroundStyle(Theme.zoneInRange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Target lower", thresholds.targetLower))
                .foregroundStyle(Theme.zoneInRange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(sorted) { reading in
                AreaMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.valueMgdL)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.valueMgdL)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            // Tide-style extreme callouts: a dot on the curve with the value
            // and time stacked beside it — above crests, below troughs. Hidden
            // while scrubbing so they don't fight the scrub callout.
            if selectedDate == nil {
                ForEach(extremes) { extreme in
                    PointMark(x: .value("Time", extreme.date), y: .value("Glucose", extreme.value))
                        .symbolSize(36)
                        .foregroundStyle(zoneColor(extreme.value))
                        .annotation(
                            position: extreme.kind == .peak ? .top : .bottom,
                            spacing: 2,
                            // Fit INSIDE the plot: the plot is clipped (so the
                            // fill can't bleed under the hour labels), and a
                            // label allowed to overflow it would be cut off.
                            overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                        ) {
                            extremeLabel(extreme)
                        }
                }
            }

            if let last = sorted.last {
                if compact {
                    PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                        .symbolSize(60)
                        .foregroundStyle(zoneColor(last.valueMgdL).opacity(0.18))
                    PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                        .symbolSize(24)
                        .foregroundStyle(zoneColor(last.valueMgdL))
                } else {
                    // Tide-style "now" marker: a soft glow, a bold zone-colored
                    // ring, and a background-filled core so it reads as a ring
                    // sitting on the curve.
                    PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                        .symbolSize(170)
                        .foregroundStyle(zoneColor(last.valueMgdL).opacity(0.18))
                    PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                        .symbolSize(92)
                        .foregroundStyle(zoneColor(last.valueMgdL))
                    PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                        .symbolSize(38)
                        .foregroundStyle(Theme.background)
                }
            }

            if let sel = selectedReading {
                RuleMark(x: .value("Selected", sel.timestamp))
                    .foregroundStyle(Theme.textTertiary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    // Fit inside the clipped plot — with the old y: .disabled the
                    // callout sat above the plot's top edge and the clip swallowed
                    // it, so scrubbing showed the line but no value.
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        scrubCallout(sel)
                    }
                PointMark(x: .value("Selected", sel.timestamp), y: .value("Glucose", sel.valueMgdL))
                    .symbolSize(120)
                    .foregroundStyle(thresholds.zone(forMgdL: sel.valueMgdL).color)
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // The full-size chart hides the y-axis entirely — the on-curve extreme
        // labels carry the values, tide-chart style. Only the compact variant
        // (no annotations) keeps a small axis. Conditional CONTENT rather than a
        // stacked visibility modifier, so exactly one axis definition applies.
        .chartYAxis {
            if compact {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let mgdL = value.as(Double.self) {
                            Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                        }
                    }
                }
            }
        }
        .chartXAxis {
            // Whole-hour ticks with a window-dependent stride: automatic marks can
            // land at sub-hour points, which an hour-only format renders as
            // duplicates ("5:00, 5:00, 6:00, 6:00"). A tick separates the plot
            // floor from the labels.
            AxisMarks(values: .stride(by: .hour, count: xStrideHours)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
                AxisTick(length: 4).foregroundStyle(Theme.hairline)
                AxisValueLabel(format: xLabelFormat)
            }
        }
        // Keep every mark inside the plot area: the area fill and the smoothed
        // (Catmull-Rom) curve must end above the hour labels, never bleed past
        // the plot's floor into the axis strip or the card below it.
        .chartPlotStyle { plot in plot.clipped() }
        .frame(height: compact ? 120 : 220)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(y: appeared ? 1 : 0.94, anchor: .bottom)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The two-line label attached to an annotated extreme: the value in the
    /// zone's colour with the time beneath, like a tide chart's crest labels.
    /// Sits on a small material chip (same treatment as the scrub callout) so it
    /// stays readable over the curve and the gradient fill.
    private func extremeLabel(_ extreme: ChartExtreme) -> some View {
        VStack(spacing: 0) {
            Text(GlucoseFormatting.string(mgdL: extreme.value, unit: unit))
                .font(.caption.weight(.bold))
                .foregroundStyle(zoneColor(extreme.value))
            Text(extreme.date, format: .dateTime.hour().minute())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
    }

    private func scrubCallout(_ reading: GlucoseReading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(GlucoseFormatting.labeled(mgdL: reading.valueMgdL, unit: unit))
                .font(.caption.weight(.bold))
                .foregroundStyle(thresholds.zone(forMgdL: reading.valueMgdL).color)
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
    }

    /// The x-range with a little trailing headroom (3% of the window, at least
    /// two minutes), so the "now" marker sits inside the plot instead of being
    /// halved by the clip at the right edge.
    private var xDomain: ClosedRange<Date> {
        guard let first = sorted.first?.timestamp, let last = sorted.last?.timestamp else {
            let now = Date()
            return now.addingTimeInterval(-3600)...now
        }
        let pad = max(120, last.timeIntervalSince(first) * 0.03)
        return first...last.addingTimeInterval(pad)
    }

    private var yDomain: ClosedRange<Double> {
        // The full-size chart pads a little extra so the extreme labels
        // (drawn above peaks and below valleys) have head- and foot-room.
        let pad: Double = compact ? 20 : 30
        let values = sorted.map(\.valueMgdL)
        let low = min(values.min() ?? thresholds.targetLower, thresholds.targetLower) - pad
        let high = max(values.max() ?? thresholds.targetUpper, thresholds.targetUpper) + pad
        return max(0, low)...high
    }

    /// Hours between hour-aligned x-axis ticks, keeping ~4–6 unique labels for
    /// any window (3h→1, 6h→2, 12h→3, 24h→6, multi-day custom→12).
    private var xStrideHours: Int {
        guard let first = sorted.first?.timestamp, let last = sorted.last?.timestamp else { return 1 }
        let hours = last.timeIntervalSince(first) / 3600
        switch hours {
        case ..<4: return 1
        case ..<9: return 2
        case ..<15: return 3
        case ..<27: return 6
        default: return 12
        }
    }

    /// Hour-only labels within a day; day + hour once a custom window spans more,
    /// so two ticks a day apart can't read identically.
    private var xLabelFormat: Date.FormatStyle {
        guard let first = sorted.first?.timestamp, let last = sorted.last?.timestamp,
              last.timeIntervalSince(first) > 27 * 3600
        else { return .dateTime.hour() }
        return .dateTime.day().hour()
    }
}

/// Fades and lifts a view in with a spring the first time it appears — used to
/// give charts and cards a bit of life without any per-call boilerplate.
private struct AppearTransition: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Spring fade-and-rise when the view first appears.
    func appearTransition(delay: Double = 0) -> some View {
        modifier(AppearTransition(delay: delay))
    }
}

#Preview("Trend chart — annotated extremes") {
    // Twelve hours of 15-minute readings shaped like a tide curve: a deep
    // early-morning valley, a tall post-breakfast peak, then a smaller dip and
    // rise — so the preview shows all four annotated extremes plus the ringed
    // "now" dot on the full-size chart, and the plain compact variant below.
    let wave: [Double] = [
        118, 112, 105, 96, 88, 79, 72, 68, 64, 62, 65, 74,
        88, 104, 122, 141, 158, 172, 183, 191, 196, 198, 195, 188,
        178, 166, 152, 138, 124, 112, 103, 98, 96, 99, 106, 116,
        128, 141, 152, 161, 167, 170, 168, 162, 153, 143, 134, 127, 122,
    ]
    let now = Date()
    let readings = wave.enumerated().map { index, value in
        GlucoseReading(
            valueMgdL: value,
            timestamp: now.addingTimeInterval(Double(index) * 15 * 60 - 12 * 3600)
        )
    }
    return VStack(spacing: 24) {
        GlucoseTrendChart(readings: readings, thresholds: .standard, unit: .mgdL)
        GlucoseTrendChart(readings: readings, thresholds: .standard, unit: .mgdL, compact: true)
    }
    .padding()
    .background(Theme.background)
}
