import SwiftUI
import Charts

/// The dashboard hero: a circular gauge showing the current glucose value,
/// tinted by its zone, with the trend arrow beneath.
struct GlucoseGaugeRing: View {
    let mgdL: Double
    let zone: GlucoseZone
    let unit: GlucoseUnit
    var trend: GlucoseTrend?
    /// Sized for the card-less hero: with no frame around it, the ring can own
    /// the top of the screen (device feedback: "bigger, more refined").
    var diameter: CGFloat = 248

    /// Display scale for the ring sweep (clamped).
    private let scaleLow = 40.0
    private let scaleHigh = 320.0
    private let ringWidth: CGFloat = 16

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
                .stroke(zone.color.opacity(0.35), lineWidth: ringWidth)
                .blur(radius: 12)
                .scaleEffect(pulse ? 1.05 : 0.97)
                .opacity(pulse ? 0.8 : 0.4)

            // A faint instrument tick ring just inside the track — the quiet
            // "dial" detail that makes the gauge read as crafted, not generic.
            ForEach(0..<60, id: \.self) { index in
                Rectangle()
                    .fill(Theme.textSecondary.opacity(index.isMultiple(of: 15) ? 0.35 : 0.16))
                    .frame(width: 1.5, height: index.isMultiple(of: 15) ? 7 : 4)
                    .offset(y: -diameter / 2 + ringWidth + 13)
                    .rotationEffect(.degrees(Double(index) * 6))
            }

            Circle()
                .stroke(Theme.hairline.opacity(0.7), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            // The sweep brightens toward its tip, giving the arc direction.
            Circle()
                .trim(from: 0, to: appeared ? fraction : 0)
                .stroke(
                    AngularGradient(
                        colors: [zone.color.opacity(0.45), zone.color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(fraction * 360)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)

            // A bright cap at the arc's tip — the "you are here" of the scale.
            tipDot

            VStack(spacing: 2) {
                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 34)
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

    /// The glowing endpoint of the sweep, riding exactly on the arc's tip.
    private var tipDot: some View {
        let angle = (fraction * 360 - 90) * .pi / 180
        let radius = diameter / 2
        return Circle()
            .fill(zone.color)
            .frame(width: ringWidth - 4, height: ringWidth - 4)
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: zone.color.opacity(0.8), radius: 5)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(appeared ? 1 : 0)
            .animation(.smooth, value: fraction)
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

/// A live, breathing ring for the latest reading: a soft ping that keeps expanding
/// and fading out around the current point, so the chart reads as alive. Drawn over
/// the existing static "now" dot, so the dot stays put and only the halo animates.
private struct PulsingLiveDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.6), lineWidth: 2)
            .frame(width: 12, height: 12)
            .scaleEffect(pulsing ? 2.6 : 0.7)
            .opacity(pulsing ? 0 : 0.85)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

struct GlucoseTrendChart: View {
    let readings: [GlucoseReading]
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit
    var compact = false
    /// Non-glucose events to pin on the chart, and which kinds are visible.
    var events: [ChartEvent] = []
    var visibleEventKinds: Set<ChartEventKind> = []
    /// When provided (full-size charts), an ⓘ button opens the show/hide legend.
    var eventKindsBinding: Binding<Set<ChartEventKind>>? = nil
    /// When true, events are shown as a slim lane BELOW the chart (aligned to the
    /// same time axis) instead of tiny badges on the curve — which get lost
    /// against the area fill. Per device feedback ("a band under the chart").
    var eventBand: Bool = false
    /// Yesterday's readings (raw, un-shifted). Drawn as a faint grey ghost line
    /// under today's curve, time-shifted +24h onto today's axis — instant
    /// context for "is today usual?". Empty hides the ghost.
    var yesterday: [GlucoseReading] = []

    @State private var selectedDate: Date?
    @State private var appeared = false
    @State private var showingLegend = false
    /// Drives the one-shot left-to-right draw-on sweep.
    @State private var drawn = false
    /// The zone under the finger during a scrub, so crossing into/out of the
    /// target band gets its own, firmer haptic.
    @State private var scrubZoneWasInRange: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sorted: [GlucoseReading] {
        readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }
    }

    /// The readings actually drawn as area/line marks — downsampled so a wide
    /// window (a year ≈ 105k points) doesn't emit hundreds of thousands of marks
    /// and stall the main thread. Scrubbing, extreme callouts and the "now" dot
    /// still read the full-fidelity `sorted` set.
    private var marks: [GlucoseReading] {
        GlucoseDownsampler.downsample(sorted, maxPoints: compact ? 160 : 480)
    }

    /// Whether scrubbing / detailed marks are enabled (full-size only).
    private var interactive: Bool { !compact }

    /// Yesterday's curve shifted onto today's time axis, downsampled hard — it
    /// is context, not data, so a coarse line is enough. Full-size charts only.
    private var yesterdayMarks: [(id: Int, date: Date, mgdL: Double)] {
        guard interactive, !yesterday.isEmpty else { return [] }
        let shifted = yesterday.filter(\.isActive)
            .sorted { $0.timestamp < $1.timestamp }
        return GlucoseDownsampler.downsample(shifted, maxPoints: 160)
            .enumerated()
            .map { ($0.offset, $0.element.timestamp.addingTimeInterval(86_400), $0.element.valueMgdL) }
    }

    /// The soft-edged target band: in-range green fading out toward both limits
    /// instead of hard edges.
    private var softBandGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Theme.zoneInRange.opacity(0), location: 0),
                .init(color: Theme.zoneInRange.opacity(0.09), location: 0.3),
                .init(color: Theme.zoneInRange.opacity(0.09), location: 0.7),
                .init(color: Theme.zoneInRange.opacity(0), location: 1),
            ]),
            startPoint: .bottom, endPoint: .top
        )
    }

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

    /// Events whose kind is currently visible (full-size charts only).
    private var visibleEvents: [ChartEvent] {
        guard interactive else { return [] }
        return events.filter { visibleEventKinds.contains($0.kind) }
    }

    /// Whether to render the separate event lane beneath the chart (opted in,
    /// full-size, and there is at least one visible event to show).
    private var showEventBand: Bool {
        eventBand && interactive && !visibleEvents.isEmpty
    }

    /// A y just above the plot floor, where the event markers sit in a row.
    private var markerY: Double {
        let d = yDomain
        return d.lowerBound + (d.upperBound - d.lowerBound) * 0.05
    }

    /// The ⓘ legend/toggle button — only on full-size charts given a binding.
    @ViewBuilder private var legendButton: some View {
        if let eventKindsBinding, !compact {
            Button {
                Haptics.play(.light)
                showingLegend = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chart markers")
            .sheet(isPresented: $showingLegend) {
                ChartEventLegend(visible: eventKindsBinding)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
        Chart {
            // Threshold lines carry the colour of the zone they border, so the
            // top dashed line reads as the high limit and the bottom one as the
            // low limit at a glance (matching how readings are tinted).
            //
            // With a night target set, the two limits become stepped lines that
            // follow the effective band at each reading's time — so the target
            // visibly narrows/shifts across the night window.
            if thresholds.nightModeEnabled {
                ForEach(marks) { reading in
                    LineMark(x: .value("Time", reading.timestamp),
                             y: .value("High limit", thresholds.targetUpper(at: reading.timestamp)),
                             series: .value("Band", "upper"))
                        .foregroundStyle(Theme.zoneHigh.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .interpolationMethod(.stepEnd)
                    LineMark(x: .value("Time", reading.timestamp),
                             y: .value("Low limit", thresholds.targetLower(at: reading.timestamp)),
                             series: .value("Band", "lower"))
                        .foregroundStyle(Theme.zoneWarning.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .interpolationMethod(.stepEnd)
                }
            } else {
                // The target band as a soft wash that fades toward both limits —
                // no hard edges — with the dashed limit lines on top of it.
                RectangleMark(
                    yStart: .value("Target lower", thresholds.targetLower),
                    yEnd: .value("Target upper", thresholds.targetUpper)
                )
                .foregroundStyle(softBandGradient)
                RuleMark(y: .value("Target upper", thresholds.targetUpper))
                    .foregroundStyle(Theme.zoneHigh.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(y: .value("Target lower", thresholds.targetLower))
                    .foregroundStyle(Theme.zoneWarning.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // Yesterday's ghost: a faint grey line under today's curve, shifted
            // onto the same axis. Context at a glance, never competing for
            // attention (and toggleable in Appearance).
            ForEach(yesterdayMarks, id: \.id) { mark in
                LineMark(
                    x: .value("Time", mark.date),
                    y: .value("Yesterday", mark.mgdL),
                    series: .value("Series", "yesterday")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.textSecondary.opacity(0.22))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            ForEach(marks) { reading in
                AreaMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.valueMgdL)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.valueMgdL),
                    series: .value("Series", "today")
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

            // Event markers: a row of tinted symbol badges near the plot floor,
            // one per visible non-glucose event (insulin, meal, med, …). Skipped
            // when the separate event lane below is in use (they move down there).
            if !showEventBand {
                ForEach(visibleEvents) { event in
                    PointMark(x: .value("Event", event.date), y: .value("Marker", markerY))
                        .symbolSize(0)
                        .annotation(position: .overlay, alignment: .center, spacing: 0) {
                            Image(systemName: event.kind.symbol)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(event.kind.color, in: .circle)
                                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1))
                        }
                }
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // A live, pulsing "now" ring at the latest reading — a soft ping that keeps
        // expanding and fading so the current point visibly breathes. Drawn in a
        // real SwiftUI overlay (not a static chart symbol) so the animation runs.
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let last = sorted.last,
                   let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: last.timestamp),
                   let y = proxy.position(forY: last.valueMgdL) {
                    let rect = geo[plotFrame]
                    PulsingLiveDot(color: zoneColor(last.valueMgdL))
                        .position(x: rect.minX + x, y: rect.minY + y)
                }
            }
            .allowsHitTesting(false)
        }
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
        .overlay(alignment: .topTrailing) { legendButton }

            if showEventBand {
                eventBandView
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(y: appeared ? 1 : 0.94, anchor: .bottom)
        // The one-shot draw-on: everything sweeps in left → right, once, as if
        // the pen were drawing the day. Skipped under Reduce Motion.
        .mask {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().frame(width: geo.size.width * (drawn ? 1 : 0))
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
            if reduceMotion || compact {
                drawn = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) { drawn = true }
            }
        }
        // Scrub feedback: a light tick per reading, and a firmer knock the
        // moment the finger crosses into or out of the target band.
        .onChange(of: selectedReading?.id) { _, _ in
            guard let sel = selectedReading else {
                scrubZoneWasInRange = nil
                return
            }
            let inRange = sel.valueMgdL >= thresholds.targetLower(at: sel.timestamp)
                && sel.valueMgdL <= thresholds.targetUpper(at: sel.timestamp)
            if let was = scrubZoneWasInRange, was != inRange {
                Haptics.play(.warning)
            } else {
                Haptics.play(.selection)
            }
            scrubZoneWasInRange = inRange
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// A slim lane beneath the chart that lines each non-glucose event (insulin,
    /// meal, medication, …) up on the SAME time axis as the curve above. Uses the
    /// chart's `xDomain`, so a badge sits directly under the moment it happened —
    /// clearer than the tiny on-curve markers that vanished against the area fill.
    private var eventBandView: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(Theme.hairline.opacity(0.5))
                .frame(height: 0.5)
            Chart {
                ForEach(visibleEvents) { event in
                    PointMark(x: .value("Time", event.date), y: .value("Lane", 0))
                        .symbolSize(0)
                        .annotation(position: .overlay, alignment: .center, spacing: 0) {
                            Image(systemName: event.kind.symbol)
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(event.kind.color, in: .circle)
                                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1.5))
                        }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: -1...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 22)
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    /// The two-line label attached to an annotated extreme: the value in the
    /// zone's colour with the time beneath, like a tide chart's crest labels.
    /// Plain floating text — no frame, no box, and no halo (the soft
    /// background-coloured halo read as a faint rounded box over the fill).
    private func extremeLabel(_ extreme: ChartExtreme) -> some View {
        VStack(spacing: 0) {
            Text(GlucoseFormatting.string(mgdL: extreme.value, unit: unit))
                .font(.caption.weight(.bold))
                .foregroundStyle(zoneColor(extreme.value))
            Text(extreme.date, format: .dateTime.hour().minute())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func scrubCallout(_ reading: GlucoseReading) -> some View {
        // Plain floating text — no frame, no box, no halo. Just the value in its
        // zone colour with the time beneath, tracking the finger across the curve.
        VStack(alignment: .leading, spacing: 1) {
            Text(GlucoseFormatting.labeled(mgdL: reading.valueMgdL, unit: unit))
                .font(.caption.weight(.bold))
                .foregroundStyle(thresholds.zone(forMgdL: reading.valueMgdL).color)
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
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

    /// Hours between hour-aligned x-axis ticks, scaled to keep ~4–6 readable,
    /// non-overlapping labels for ANY window — from a few hours up to a year.
    /// The old version capped the step at 12h, so a month (~720h) drew ~60 ticks
    /// and a year hundreds, all piling into an unreadable band. Beyond a day the
    /// step now snaps to whole-day multiples so week/month/year windows show a
    /// handful of dated ticks instead.
    private var xStrideHours: Int {
        guard let first = sorted.first?.timestamp, let last = sorted.last?.timestamp else { return 1 }
        let hours = max(1, last.timeIntervalSince(first) / 3600)
        let target = hours / 5   // aim for ~5 evenly spaced ticks
        let steps = [1, 2, 3, 6, 12, 24, 48, 72, 24 * 5, 24 * 7, 24 * 14, 24 * 30, 24 * 60, 24 * 90, 24 * 180, 24 * 365]
        return steps.first { Double($0) >= target } ?? steps.last!
    }

    /// Window-adaptive label: times within a day, "Jul 22" for day-to-season
    /// windows, and "Jul 26" once the window spans seasons — so two ticks a step
    /// apart never read identically or pile up.
    private var xLabelFormat: Date.FormatStyle {
        guard let first = sorted.first?.timestamp, let last = sorted.last?.timestamp else {
            return .dateTime.hour()
        }
        let hours = last.timeIntervalSince(first) / 3600
        switch hours {
        case ..<27:      return .dateTime.hour()          // within a day
        case ..<2160:    return .dateTime.month(.abbreviated).day()          // up to ~90 days
        default:         return .dateTime.month(.abbreviated).year(.twoDigits)
        }
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
