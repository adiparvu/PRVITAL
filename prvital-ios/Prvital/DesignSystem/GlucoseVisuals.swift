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
/// Swift Charts. Values are plotted in mg/dL and the axis is formatted to the
/// display unit. The full-size variant fills the curve with a gradient, lets
/// you scrub with a finger to read any point, and fades in on appear.
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

                if interactive {
                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.valueMgdL)
                    )
                    .symbolSize(20)
                    .foregroundStyle(thresholds.zone(forMgdL: reading.valueMgdL).color)
                }
            }

            if let last = sorted.last {
                PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                    .symbolSize(compact ? 60 : 140)
                    .foregroundStyle(thresholds.zone(forMgdL: last.valueMgdL).color.opacity(0.18))
                PointMark(x: .value("Time", last.timestamp), y: .value("Glucose", last.valueMgdL))
                    .symbolSize(compact ? 24 : 44)
                    .foregroundStyle(thresholds.zone(forMgdL: last.valueMgdL).color)
            }

            if let sel = selectedReading {
                RuleMark(x: .value("Selected", sel.timestamp))
                    .foregroundStyle(Theme.textTertiary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        scrubCallout(sel)
                    }
                PointMark(x: .value("Selected", sel.timestamp), y: .value("Glucose", sel.valueMgdL))
                    .symbolSize(120)
                    .foregroundStyle(thresholds.zone(forMgdL: sel.valueMgdL).color)
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 5)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let mgdL = value.as(Double.self) {
                        Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
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

    private var yDomain: ClosedRange<Double> {
        let values = sorted.map(\.valueMgdL)
        let low = min(values.min() ?? thresholds.targetLower, thresholds.targetLower) - 20
        let high = max(values.max() ?? thresholds.targetUpper, thresholds.targetUpper) + 20
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
