import SwiftUI
import Charts

/// The dashboard's first screen, tide-guide style: a big glass dial with the
/// live reading (and IOB / COB as satellite bubbles), and below it the day's
/// glucose as a smooth full-width wave with the peak and trough annotated.
/// Everything the app already shows stays untouched below — this section simply
/// fills the first viewport, and the familiar dashboard appears on scroll.
struct TideHeroSection: View {
    let valueText: String
    let unitText: String
    let trendSymbol: String
    let trendLabel: String
    let zoneColor: Color
    /// The quiet line under the value: an imminent-low/high prediction when
    /// there is one, the zone label otherwise.
    let caption: String
    let currentMgdL: Double
    let targetLowerMgdL: Double
    let targetUpperMgdL: Double
    let iobText: String?
    let cobText: String?
    /// Ascending points of the wave window, plus the optional forecast tail.
    let points: [TidePoint]
    let forecast: TidePoint?
    let unit: GlucoseUnit

    var body: some View {
        VStack(spacing: 0) {
            GlucoseHeroDial(
                valueText: valueText, unitText: unitText,
                trendSymbol: trendSymbol, trendLabel: trendLabel,
                zoneColor: zoneColor, caption: caption,
                fraction: TideHeroMath.gaugeFraction(mgdL: currentMgdL),
                band: TideHeroMath.bandFractions(lowerMgdL: targetLowerMgdL, upperMgdL: targetUpperMgdL),
                iobText: iobText, cobText: cobText
            )
            .padding(.top, 6)

            Spacer(minLength: 16)

            GlucoseWaveChart(points: points, forecast: forecast, zoneColor: zoneColor, unit: unit)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                // The wave runs edge to edge like a tide chart; escape the
                // scroll content's horizontal padding.
                .padding(.horizontal, -16)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Dial

/// The glass compass-dial: ticks around the rim, the target band as a green
/// arc, a pointer at the current value's position on the scale, the reading in
/// the middle, and IOB / COB floating alongside as satellite bubbles.
private struct GlucoseHeroDial: View {
    let valueText: String
    let unitText: String
    let trendSymbol: String
    let trendLabel: String
    let zoneColor: Color
    let caption: String
    /// Current value's position on the gauge (0...1).
    let fraction: Double
    /// The in-range band on the gauge, nil when thresholds are degenerate.
    let band: ClosedRange<Double>?
    let iobText: String?
    let cobText: String?

    /// The gauge occupies a 240° sweep starting at 150° (SwiftUI degrees:
    /// clockwise from "east"), the classic bottom-open dial.
    private let sweepDeg: Double = 240
    private let startDeg: Double = 150
    private let dialSize: CGFloat = 286

    var body: some View {
        ZStack {
            // The glass disc, same material language as the app's cards.
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))

            ticks

            if let band {
                Circle()
                    .trim(from: band.lowerBound * sweepDeg / 360,
                          to: band.upperBound * sweepDeg / 360)
                    .stroke(Theme.zoneInRange.opacity(0.75),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(startDeg))
                    .padding(7)
            }

            pointer

            VStack(spacing: 5) {
                Label {
                    Text("Glucose")
                } icon: {
                    Image(systemName: "drop.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(valueText)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(zoneColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unitText)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: trendSymbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(zoneColor)
                        .contentTransition(.symbolEffect(.replace))
                    Text(trendLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 28)
            }
        }
        .frame(width: dialSize, height: dialSize)
        // The satellite bubbles float just outside the dial, like the wind /
        // swell bubbles on a tide dial: insulin-on-board lower-left,
        // carbs-on-board upper-right. Only shown when there is a value.
        .overlay(alignment: .center) {
            if let iobText {
                SatelliteBubble(value: iobText, label: String(localized: "Insulin"))
                    .offset(bubbleOffset(angleDeg: 152))
            }
        }
        .overlay(alignment: .center) {
            if let cobText {
                SatelliteBubble(value: cobText, label: String(localized: "Carbs"))
                    .offset(bubbleOffset(angleDeg: -22))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(valueText) \(unitText), \(trendLabel). \(caption)")
    }

    private var ticks: some View {
        ForEach(0..<48, id: \.self) { index in
            Rectangle()
                .fill(Theme.textSecondary.opacity(index.isMultiple(of: 12) ? 0.55 : 0.28))
                .frame(width: 1.5, height: index.isMultiple(of: 12) ? 9 : 5)
                .offset(y: -dialSize / 2 + 11)
                .rotationEffect(.degrees(Double(index) / 48 * 360))
        }
    }

    /// The current-value pointer: a small zone-coloured triangle sitting just
    /// inside the rim at the value's position, aimed at the centre.
    private var pointer: some View {
        let angle = startDeg + fraction * sweepDeg
        let radians = angle * .pi / 180
        let radius = dialSize / 2 - 22
        return Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 11))
            .foregroundStyle(zoneColor)
            // The glyph points down by default (i.e. toward the centre when it
            // sits at the top, 270°); rotate it to keep aiming inward.
            .rotationEffect(.degrees(angle - 270))
            .offset(x: cos(radians) * radius, y: sin(radians) * radius)
            .animation(.snappy, value: fraction)
    }

    /// Offset for a bubble floating just outside the dial at `angleDeg`
    /// (SwiftUI degrees, clockwise from east).
    private func bubbleOffset(angleDeg: Double) -> CGSize {
        let radians = angleDeg * .pi / 180
        let radius = dialSize / 2 + 30
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}

/// A small floating glass bubble: bold value over a tiny caption — the tide
/// dial's "19 WIND" satellites, carrying IOB / COB here.
private struct SatelliteBubble: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(6)
        .frame(width: 58, height: 58)
        .background(.ultraThinMaterial, in: .circle)
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Wave

/// The day's glucose as a tide curve: a smooth full-width wave with a soft area
/// fill, the peak and trough annotated with their time and value, the current
/// reading pulsing, and the forecast continuing as a dashed tail.
private struct GlucoseWaveChart: View {
    let points: [TidePoint]
    let forecast: TidePoint?
    let zoneColor: Color
    let unit: GlucoseUnit

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.mgdL)
        if let forecast { values.append(forecast.mgdL) }
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return 40...200 }
        // Generous headroom so the annotations above the peak / below the
        // trough never clip against the plot edge.
        let pad = max((hi - lo) * 0.35, 18)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        let extremes = TideHeroMath.extremes(of: points)
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Glucose", point.mgdL)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.42), Theme.accent.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Glucose", point.mgdL),
                    series: .value("Series", "history")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // The forecast continues the wave as a dashed accent tail — the
            // "future" half of the tide curve, honest about being projected.
            if let forecast, let last = points.last {
                ForEach([last, forecast], id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.mgdL),
                        series: .value("Series", "forecast")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [4, 4]))
                }
            }

            // High tide: time above, value under the dot.
            if let high = extremes.high {
                PointMark(x: .value("Time", high.date), y: .value("Glucose", high.mgdL))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 6) {
                        Text(high.date, format: .dateTime.hour().minute())
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .annotation(position: .bottom, spacing: 6) {
                        Text(GlucoseFormatting.string(mgdL: high.mgdL, unit: unit))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
            }

            // Low tide: value above the dot, time under it.
            if let low = extremes.low {
                PointMark(x: .value("Time", low.date), y: .value("Glucose", low.mgdL))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 6) {
                        Text(GlucoseFormatting.string(mgdL: low.mgdL, unit: unit))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .annotation(position: .bottom, spacing: 6) {
                        Text(low.date, format: .dateTime.hour().minute())
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
            }

            // The living "now": a zone-coloured dot with a soft halo; the real
            // pulse rides on top via the chart overlay.
            if let last = points.last {
                PointMark(x: .value("Time", last.date), y: .value("Glucose", last.mgdL))
                    .foregroundStyle(zoneColor.opacity(0.25))
                    .symbolSize(150)
                PointMark(x: .value("Time", last.date), y: .value("Glucose", last.mgdL))
                    .foregroundStyle(zoneColor)
                    .symbolSize(42)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let last = points.last,
                   let plot = proxy.plotFrame,
                   let px = proxy.position(forX: last.date),
                   let py = proxy.position(forY: last.mgdL) {
                    let frame = geo[plot]
                    WavePulseRing(color: zoneColor)
                        .position(x: frame.minX + px, y: frame.minY + py)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("Glucose history, last \(points.count) readings")
    }
}

/// The expanding pulse ring on the wave's current point — the same "it's alive"
/// beat as the trend chart's live dot.
private struct WavePulseRing: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.6), lineWidth: 2)
            .frame(width: 14, height: 14)
            .scaleEffect(pulsing ? 2.4 : 0.7)
            .opacity(pulsing ? 0 : 0.85)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}
