import SwiftUI
import Charts
import Accessibility

/// The dashboard hero: a circular gauge showing the current glucose value,
/// tinted by its zone, with the trend arrow beneath.
struct GlucoseGaugeRing: View {
    let mgdL: Double
    let zone: GlucoseZone
    let unit: GlucoseUnit
    var trend: GlucoseTrend?
    /// Where glucose stood an hour ago. Draws a quiet trail along the dial from
    /// there to the bead, so the direction AND the size of the last hour's move
    /// read straight off the ring — not only from the arrow.
    var previousMgdL: Double?
    /// An active rule-of-15 recheck deadline: shows a live countdown inside the
    /// gauge, under the trend (device feedback: the timer belongs on Home).
    var recheckAt: Date?
    /// Draws the zone label under the ring (device feedback: "«în interval» să
    /// fie sub cerc ca și înainte").
    var showsZoneLabel: Bool = true
    /// The user's target band, marked as a brighter segment of the track, so the
    /// bead's position reads against the goal and not just against the scale.
    var targetRange: ClosedRange<Double>?
    /// Sized for the card-less hero: with no frame around it, the ring can own
    /// the top of the screen (device feedback: "bigger, more refined").
    var diameter: CGFloat = 248

    /// A COMPLETE circle, running clockwise — the Activity-ring language
    /// everyone already reads. It replaced a 270° dial with an opening at the
    /// bottom, which left the ring looking cut (device feedback).
    private static let sweepDegrees: Double = 360

    /// Display scale for the ring sweep (clamped).
    private let scaleLow = 40.0
    private let scaleHigh = 320.0
    private let ringWidth: CGFloat = 16
    /// The hour trail rides on its own rail, in the clear band between the
    /// track's inner edge and the tick ring — never over the sweep, which would
    /// read as a scratch across it.
    private let trailInset: CGFloat = 32
    private let trailWidth: CGFloat = 3.5

    @State private var pulse = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { position(of: mgdL) }

    /// Where the scale begins on the screen circle (0° is three o'clock).
    ///
    /// The dial is oriented so the TARGET BAND straddles twelve o'clock: an
    /// in-range value therefore sits at the top, where the eye reads "good",
    /// lows swing round to the left and highs to the right. The 270° dial got
    /// that for free from its opening; closing the ring lost it, and a plain
    /// twelve-o'clock start parked a perfectly healthy 125 down at four
    /// o'clock, which reads as though something were wrong (device feedback:
    /// "bila nu este poziționată unde trebuie").
    ///
    /// Falls back to twelve o'clock when no target band was supplied.
    private var startDegrees: Double {
        guard let targetArc else { return -90 }
        let middle = (targetArc.lowerBound + targetArc.upperBound) / 2
        return -90 - middle * Self.sweepDegrees
    }

    var body: some View {
        // Generous, so the zone label reads as its own line under the hero and
        // never touches the ring (device feedback twice: "mai jos, nu să se
        // suprapună cu cercul"). The rings themselves are now pinned inside the
        // dial's frame, which was the real cause of the collision; this clears
        // the glow on top of that, which still breathes out to 21pt past the
        // frame at the peak of its pulse.
        VStack(spacing: 26) {
            dial
            // Under the ring, where it was before — not tucked into a gap in it.
            if showsZoneLabel {
                // The dial's own accessibility label already names the zone;
                // a second element would just repeat it.
                ZonePill(zone: zone, plain: true).accessibilityHidden(true)
            }
        }
    }

    private var dial: some View {
        ZStack {
            // Soft glow that breathes behind the ring, tinted by the zone.
            // Drawn as a radial gradient, NOT a blurred stroke: this pulses
            // forever, and animating a `.blur` forces an offscreen Gaussian
            // pass on every frame — the GPU never rested while the Dashboard
            // was on screen. The gradient is a plain cached fill.
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: zone.color.opacity(0), location: 0.62),
                        .init(color: zone.color.opacity(0.35), location: 0.86),
                        .init(color: zone.color.opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2 + 14
                ))
                .frame(width: diameter + 28, height: diameter + 28)
                .scaleEffect(pulse ? 1.05 : 0.97)
                .opacity(pulse ? 0.8 : 0.4)

            // A faint instrument tick ring just inside the track — the quiet
            // "dial" detail that makes the gauge read as crafted, not generic.
            // Sixty of them now, all the way round, with a longer one at each
            // quarter.
            ForEach(0..<60, id: \.self) { index in
                let major = index.isMultiple(of: 15)
                Rectangle()
                    .fill(Theme.textSecondary.opacity(major ? 0.35 : 0.16))
                    .frame(width: 1.5, height: major ? 7 : 4)
                    .offset(y: -diameter / 2 + ringWidth + 13)
                    .rotationEffect(.degrees(Double(index) / 60 * 360))
            }

            // The unlit track — a complete circle.
            //
            // EVERY ring is pinned to `diameter` explicitly. Without a frame a
            // `Circle` is flexible, so it grew to the ZStack's own size — and
            // the ZStack is sized by its largest child, the glow, at
            // `diameter + 28`. The rings were therefore drawn 28pt wider than
            // the ticks, the hour trail and the bead, all of which are placed
            // from `diameter` in points. That single mismatch is both bugs the
            // device reported: the bead sat a ring's width inside the track,
            // and the rings spilled past their own frame far enough to run into
            // the zone label underneath.
            Circle()
                .stroke(Theme.hairline.opacity(0.7), lineWidth: ringWidth)
                .frame(width: diameter, height: diameter)

            // Where the target band falls on the scale, lit faintly into the
            // track: the bead's position now reads against the goal, not only
            // against the 40–320 scale.
            if let targetArc {
                Circle()
                    .trim(from: targetArc.lowerBound, to: targetArc.upperBound)
                    .stroke(Theme.zoneInRange.opacity(0.22),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(startDegrees))
            }

            hourTrail

            // The sweep brightens toward its tip, giving the arc direction.
            // Butt caps, deliberately: the bead below IS the cap, and a round
            // one overshoots the trim end by half the ring width.
            Circle()
                .trim(from: 0, to: appeared ? fraction : 0)
                .stroke(
                    AngularGradient(
                        colors: [zone.color.opacity(0.45), zone.color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(fraction, 0.001) * Self.sweepDegrees)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(startDegrees))
                .animation(.smooth, value: fraction)

            // The bead seated in the track at the sweep's end.
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
                if let recheckAt {
                    recheckCountdown(recheckAt)
                }
            }
            .scaleEffect(appeared ? 1 : 0.9)
            // Dead centre now the ring is closed — the old upward nudge existed
            // only to balance the opening at the bottom.
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

    /// The rule-of-15 wait, ticking inside the gauge: "⏱ 12:34" while the wait
    /// runs, "Recheck now" once it's up — so treating a low never requires
    /// keeping the sheet open.
    private func recheckCountdown(_ recheckAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = recheckAt.timeIntervalSince(context.date)
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2.weight(.bold))
                if remaining > 0 {
                    Text(verbatim: RuleOf15.clock(remaining))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Text("Recheck now")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.zoneWarning)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.zoneWarning.opacity(0.14), in: .capsule)
            .accessibilityLabel(remaining > 0
                ? "Recheck in \(RuleOf15.clock(remaining))"
                : "Time to recheck your glucose")
        }
        .padding(.top, 4)
    }

    /// The bead: a bright pearl SET INTO the track at the sweep's end, sized to
    /// the ring so it fills the groove edge to edge, and centred on the stroke's
    /// centreline — `diameter / 2`, where SwiftUI draws an unstroked `Circle`'s
    /// path inside a `diameter`-wide frame.
    ///
    /// Placed with `.position` inside an explicit `diameter` box rather than
    /// `.offset` from wherever the ZStack happened to centre it, so it is
    /// anchored to exactly the same number as the rings above and cannot drift
    /// from them again (device feedback, twice: "bila nu este poziționată unde
    /// trebuie").
    private var tipDot: some View {
        let angle = (startDegrees + fraction * Self.sweepDegrees) * .pi / 180
        let radius = diameter / 2
        return Circle()
            .fill(.white)
            .frame(width: ringWidth - 1, height: ringWidth - 1)
            .overlay(Circle().stroke(zone.color, lineWidth: 1.5))
            .shadow(color: zone.color.opacity(0.9), radius: 6)
            .position(x: radius + cos(angle) * radius,
                      y: radius + sin(angle) * radius)
            .frame(width: diameter, height: diameter)
            .opacity(appeared ? 1 : 0)
            .animation(.smooth, value: fraction)
    }

    /// The last hour, drawn as a thin rail from where glucose stood an hour ago
    /// to where the bead is now, fading from almost nothing at the old end to
    /// solid at the bead — so which end is "now" is never in question.
    ///
    /// A trail rather than a second dot, on purpose: the scale is ~1.3° per
    /// mg/dL, so a steady hour would have parked a ghost dot right on top of the
    /// bead and read as a rendering fault. A trail just gets shorter, and
    /// disappears entirely when nothing moved — no arbitrary "only draw it if it
    /// moved more than X" threshold to tune.
    @ViewBuilder private var hourTrail: some View {
        if let previousMgdL {
            let from = position(of: previousMgdL)
            let to = fraction
            let rising = to >= from
            let lower = min(from, to)
            let upper = max(from, to)
            Circle()
                .trim(from: lower, to: upper)
                .stroke(
                    AngularGradient(
                        colors: rising
                            ? [zone.color.opacity(0.05), zone.color.opacity(0.7)]
                            : [zone.color.opacity(0.7), zone.color.opacity(0.05)],
                        center: .center,
                        startAngle: .degrees(lower * Self.sweepDegrees),
                        endAngle: .degrees(upper * Self.sweepDegrees)
                    ),
                    style: StrokeStyle(lineWidth: trailWidth, lineCap: .butt)
                )
                .frame(width: diameter - trailInset, height: diameter - trailInset)
                .rotationEffect(.degrees(startDegrees))
                .opacity(appeared ? 1 : 0)
                .animation(.smooth, value: fraction)
        }
    }

    /// The target band as a `Circle.trim` range on the same scale as the sweep,
    /// or nil when no band was supplied or it falls outside the dial's scale.
    private var targetArc: ClosedRange<Double>? {
        guard let targetRange else { return nil }
        let low = position(of: targetRange.lowerBound)
        let high = position(of: targetRange.upperBound)
        guard high > low else { return nil }
        return low...high
    }

    /// Where a glucose value sits on the dial, 0…1 of a full turn.
    private func position(of mgdL: Double) -> Double {
        min(max((mgdL - scaleLow) / (scaleHigh - scaleLow), 0), 1)
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
///
/// Shared: the trend chart overlays it on its last point, and the movement screen
/// uses it both on its chart and beside the live "now" readout.
struct PulsingLiveDot: View {
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

/// The ⓘ chart-markers button + its legend sheet, host-agnostic: full-size
/// charts overlay it on the plot by default, while a screen can instead place
/// it in its own header (the Dashboard puts it right after the range picker).
struct ChartLegendButton: View {
    let visible: Binding<Set<ChartEventKind>>
    @State private var showingLegend = false

    var body: some View {
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
            ChartEventLegend(visible: visible)
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
    /// Whether the chart draws its own ⓘ overlay in the top-right of the plot.
    /// Screens that host the button in their own header (the Dashboard places
    /// it beside the range picker, per device feedback) pass false and render
    /// `ChartLegendButton` themselves.
    var inlineLegendButton = true
    /// When true, events are shown as a slim lane BELOW the chart (aligned to the
    /// same time axis) instead of tiny badges on the curve — which get lost
    /// against the area fill. Per device feedback ("a band under the chart").
    var eventBand: Bool = false
    /// Yesterday's readings (raw, un-shifted). Drawn as a faint grey ghost line
    /// under today's curve, time-shifted +24h onto today's axis — instant
    /// context for "is today usual?". Empty hides the ghost.
    var yesterday: [GlucoseReading] = []
    /// A short-horizon forecast to draw PAST the newest reading: a dashed
    /// continuation of the curve with the plausible band shaded around it. The
    /// host passes it only when the window actually ends at the live reading —
    /// a historical window gets no future painted onto it.
    var forecast: GlucoseForecast? = nil

    @State private var selectedDate: Date?
    @State private var appeared = false
    /// The event marker held down in the band — presents its detail sheet.
    @State private var heldEvent: ChartEvent?
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

    /// The ⓘ legend/toggle button — only on full-size charts given a binding,
    /// and only when the host hasn't taken the button into its own header.
    @ViewBuilder private var legendButton: some View {
        if let eventKindsBinding, !compact, inlineLegendButton {
            ChartLegendButton(visible: eventKindsBinding)
        }
    }

    /// Where the dashed forecast continuation starts and ends. Only on
    /// full-size charts, and only when a forecast was supplied.
    private var projectionPath: (start: (Date, Double), end: (Date, Double))? {
        guard let forecast, !compact, let last = sorted.last else { return nil }
        let end = last.timestamp.addingTimeInterval(TimeInterval(forecast.horizonMinutes * 60))
        return ((last.timestamp, last.valueMgdL), (end, forecast.projectedMgdL))
    }

    var body: some View {
        VStack(spacing: 0) {
        Chart {
            // The forecast, painted as a future: the plausible band widening
            // out of the newest reading, with a dashed centre line to the
            // projected point. Drawn FIRST so the real curve and its dots stay
            // on top of it.
            if let path = projectionPath, let forecast {
                AreaMark(x: .value("Time", path.start.0),
                         yStart: .value("Low", path.start.1),
                         yEnd: .value("High", path.start.1),
                         series: .value("Band", "forecast"))
                    .foregroundStyle(Theme.accent.opacity(0.10))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Time", path.end.0),
                         yStart: .value("Low", forecast.lowMgdL),
                         yEnd: .value("High", forecast.highMgdL),
                         series: .value("Band", "forecast"))
                    .foregroundStyle(Theme.accent.opacity(0.10))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", path.start.0),
                         y: .value("Glucose", path.start.1),
                         series: .value("Series", "forecast"))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                LineMark(x: .value("Time", path.end.0),
                         y: .value("Glucose", path.end.1),
                         series: .value("Series", "forecast"))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
            }

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
                // Quiet, but it has to survive the wallpaper behind the card:
                // at 0.22 it vanished over a bright patch of photo.
                .foregroundStyle(Theme.textSecondary.opacity(0.45))
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
        // When the ceiling jumps to the next tier (a spike crossed into new
        // territory), glide there instead of snapping — the Dexcom rescale.
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: yDomain)
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
        .chartPlotStyle { plot in
            plot
                .background(Theme.chartPlotBackdrop)
                .clipped()
        }
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
        // Audio Graph: VoiceOver can PLAY the curve as rising and falling
        // pitch (rotor → Audio Graph) — the sonic equivalent of glancing at
        // the trend, for someone who can't see it.
        .accessibilityChartDescriptor(self)
    }

// MARK: - Audio Graph

extension GlucoseTrendChart: AXChartDescriptorRepresentable {
    /// Describes the trend chart to VoiceOver's Audio Graph: time on x, the
    /// glucose value on y, one continuous series — so the curve can be heard
    /// as pitch, with the same bounds the visual plot uses.
    func makeChartDescriptor() -> AXChartDescriptor {
        let start = sorted.first?.timestamp ?? Date()
        let points = sorted.map { reading in
            AXDataPoint(x: reading.timestamp.timeIntervalSince(start) / 60,
                        y: reading.valueMgdL)
        }
        let totalMinutes = max(1, (sorted.last?.timestamp.timeIntervalSince(start) ?? 0) / 60)

        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: 0...totalMinutes,
            gridlinePositions: []
        ) { minutes in
            Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        }
        let domain = yDomain
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Glucose"),
            range: domain.lowerBound...domain.upperBound,
            gridlinePositions: [thresholds.targetLower, thresholds.targetUpper]
        ) { value in
            GlucoseFormatting.labeled(mgdL: value, unit: unit)
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Glucose"),
            isContinuous: true,
            dataPoints: points)

        return AXChartDescriptor(
            title: String(localized: "Glucose trend"),
            summary: accessibilitySummary,
            xAxis: xAxis, yAxis: yAxis, series: [series])
    }
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
                            // A real view, so it can carry the hold gesture:
                            // press-and-hold opens the marker's detail sheet.
                            Image(systemName: event.kind.symbol)
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(event.kind.color, in: .circle)
                                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1.5))
                                .padding(4)          // a friendlier hit target
                                .contentShape(.circle)
                                .onLongPressGesture(minimumDuration: 0.3) {
                                    Haptics.play(.light)
                                    heldEvent = event
                                }
                                .accessibilityLabel(Text(event.kind.label))
                                .accessibilityValue(Text(event.date, format: .dateTime.hour().minute()))
                                .accessibilityAddTraits(.isButton)
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
        .sheet(item: $heldEvent) { event in
            ChartEventDetailSheet(event: event)
        }
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
        var pad = max(120, last.timeIntervalSince(first) * 0.03)
        // With a forecast drawn, the domain must reach its far end (plus a
        // touch of breathing room past the dashed tip).
        if let path = projectionPath {
            pad = max(pad, path.end.0.timeIntervalSince(last) + 120)
        }
        return first...last.addingTimeInterval(pad)
    }

    private var yDomain: ClosedRange<Double> {
        // Dexcom-style stepped scale. The old domain tracked the data max plus a
        // small pad, so a spike above the high-limit line hugged the frame edge
        // and looked like it was escaping the plot. The ceiling now snaps to the
        // next fixed tier (200 → 250 → … → 400) the moment the data or the
        // target line needs it — the whole chart visibly rescales with real
        // headroom, and stays put between tiers instead of drifting with every
        // reading. The floor snaps down to a 20 mg/dL step for the same
        // stability. Yesterday's ghost line deliberately does NOT drive the
        // scale (it's context; an outlier there just clips).
        let pad: Double = compact ? 20 : 30   // room for the extreme labels
        let values = sorted.map(\.valueMgdL)
        var dataHigh = max(values.max() ?? thresholds.targetUpper, thresholds.targetUpper)
        var dataLow = min(values.min() ?? thresholds.targetLower, thresholds.targetLower)
        // The forecast band participates in the scale, so its shaded edges are
        // never clipped by the frame.
        if projectionPath != nil, let forecast {
            dataHigh = max(dataHigh, forecast.highMgdL)
            dataLow = min(dataLow, forecast.lowMgdL)
        }
        let tiers: [Double] = [200, 250, 300, 350, 400]
        let high = tiers.first { $0 >= dataHigh + pad } ?? (dataHigh + pad)
        let low = max(0, ((dataLow - pad) / 20).rounded(.down) * 20)
        return low...high
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
