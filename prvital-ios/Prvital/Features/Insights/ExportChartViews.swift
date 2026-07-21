import SwiftUI

#if canImport(UIKit)

/// Self-contained SwiftUI charts used to rasterise a visual summary into the
/// clinician PDF export. They are built **purely** from `ExportInput` values
/// (glucose readings, thresholds, unit, `PeriodStatistics`), take a fixed frame
/// and paint an explicit light background, and read nothing from `@Environment`
/// — so they render correctly off-screen through `ImageRenderer` on a printed
/// page regardless of the device's colour scheme.
///
/// Fixed print-friendly ink colours keep text and axes legible on the white
/// page even if the rendering environment resolves to dark. The five glucose
/// zones use the shared `Theme` colours so the export matches the on-screen
/// report.
private enum ExportChartInk {
    static let primary = Color(hex: 0x11131A)
    static let secondary = Color(hex: 0x6B7280)
    static let page = Color.white
}

// MARK: - Time in range

/// A stacked horizontal Time-in-Range bar (very-low / low / in-range / high /
/// very-high) in the standard zone colours, with a per-zone percentage legend.
struct ExportTimeInRangeBar: View {
    let statistics: PeriodStatistics
    var size = CGSize(width: 500, height: 180)

    private var bands: [(color: Color, fraction: Double, label: String)] {
        let s = statistics
        let low = max(s.timeBelowRange - s.timeVeryLow, 0)
        let high = max(s.timeAboveRange - s.timeVeryHigh, 0)
        return [
            (Theme.zoneCritical, s.timeVeryLow, "Very low"),
            (Theme.zoneWarning, low, "Low"),
            (Theme.zoneInRange, s.timeInRange, "In range"),
            (Theme.zoneHigh, high, "High"),
            (Theme.zoneWarning, s.timeVeryHigh, "Very high"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time in range")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ExportChartInk.primary)

            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                        band.color
                            .frame(width: max(geo.size.width * band.fraction,
                                              band.fraction > 0 ? 2 : 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 26)

            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    legend(color: band.color, fraction: band.fraction, label: band.label)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(ExportChartInk.page)
    }

    private func legend(color: Color, fraction: Double, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text((fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ExportChartInk.primary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(ExportChartInk.secondary)
            }
        }
    }
}

// MARK: - AGP / glucose curve

/// The Ambulatory Glucose Profile: a median line with the 10–90% and 25–75%
/// percentile bands over a modal 24-hour day, when enough time-of-day buckets
/// are available. With too little data it falls back to a plain chronological
/// glucose line over the period. Rendered with `Canvas` for deterministic
/// off-screen rasterisation.
struct ExportAGPChart: View {
    let glucose: [GlucoseReading]
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit
    var size = CGSize(width: 500, height: 180)

    private var activeReadings: [GlucoseReading] { glucose.filter(\.isActive) }
    private var buckets: [AGPBucket] { AGPAggregator.buckets(glucose, binMinutes: 60) }
    /// AGP percentile data is meaningful once a handful of time-of-day buckets exist.
    private var hasAGP: Bool { buckets.count >= 3 }

    private var maxY: Double {
        let p90Max = buckets.map(\.p90).max() ?? 0
        let readingMax = activeReadings.map(\.valueMgdL).max() ?? 0
        let ceiling = max(p90Max, readingMax, thresholds.high) + 20
        return min(max(ceiling, 250), 420)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hasAGP ? "Ambulatory Glucose Profile (modal day)" : "Glucose over period")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ExportChartInk.primary)
            Canvas { ctx, canvasSize in
                draw(into: ctx, canvasSize: canvasSize)
            }
        }
        .padding(14)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(ExportChartInk.page)
    }

    private func draw(into ctx: GraphicsContext, canvasSize: CGSize) {
        let leftAxis: CGFloat = 30
        let bottomAxis: CGFloat = 14
        let plot = CGRect(x: leftAxis, y: 2,
                          width: max(canvasSize.width - leftAxis - 4, 1),
                          height: max(canvasSize.height - bottomAxis - 2, 1))
        let top = maxY

        func px(_ minutes: Double) -> CGFloat { plot.minX + CGFloat(minutes / 1440) * plot.width }
        func py(_ value: Double) -> CGFloat {
            plot.maxY - CGFloat(min(max(value, 0), top) / top) * plot.height
        }

        // Target-range shading.
        let bandRect = CGRect(x: plot.minX, y: py(thresholds.targetUpper),
                              width: plot.width,
                              height: py(thresholds.targetLower) - py(thresholds.targetUpper))
        ctx.fill(Path(bandRect), with: .color(Theme.zoneInRange.opacity(0.12)))

        // Dashed target lines.
        for level in [thresholds.targetLower, thresholds.targetUpper] {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: py(level)))
            line.addLine(to: CGPoint(x: plot.maxX, y: py(level)))
            ctx.stroke(line, with: .color(Theme.zoneInRange.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        // Y-axis value labels.
        for value in yTicks(top: top) {
            let text = Text(GlucoseFormatting.string(mgdL: value, unit: unit))
                .font(.system(size: 8)).foregroundColor(ExportChartInk.secondary)
            ctx.draw(text, at: CGPoint(x: plot.minX - 4, y: py(value)), anchor: .trailing)
        }

        if hasAGP {
            drawBand(ctx, top: \.p90, bottom: \.p10, opacity: 0.14, px: px, py: py)
            drawBand(ctx, top: \.p75, bottom: \.p25, opacity: 0.22, px: px, py: py)

            var median = Path()
            for (i, b) in buckets.enumerated() {
                let point = CGPoint(x: px(Double(b.minutesOfDay)), y: py(b.p50))
                if i == 0 { median.move(to: point) } else { median.addLine(to: point) }
            }
            ctx.stroke(median, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))

            // X-axis hour labels for the modal day.
            for hour in stride(from: 0, through: 24, by: 6) {
                let text = Text("\(hour):00").font(.system(size: 8))
                    .foregroundColor(ExportChartInk.secondary)
                ctx.draw(text, at: CGPoint(x: px(Double(hour) * 60), y: plot.maxY + 7),
                         anchor: .center)
            }
        } else {
            let ordered = activeReadings.sorted { $0.timestamp < $1.timestamp }
            if ordered.count >= 2,
               let start = ordered.first?.timestamp,
               let end = ordered.last?.timestamp {
                let span = max(end.timeIntervalSince(start), 1)
                var line = Path()
                for (i, r) in ordered.enumerated() {
                    let frac = r.timestamp.timeIntervalSince(start) / span
                    let point = CGPoint(x: plot.minX + CGFloat(frac) * plot.width,
                                        y: py(r.valueMgdL))
                    if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                ctx.stroke(line, with: .color(Theme.accent),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }

    private func drawBand(
        _ ctx: GraphicsContext,
        top: KeyPath<AGPBucket, Double>,
        bottom: KeyPath<AGPBucket, Double>,
        opacity: Double,
        px: (Double) -> CGFloat,
        py: (Double) -> CGFloat
    ) {
        guard let first = buckets.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: px(Double(first.minutesOfDay)), y: py(first[keyPath: top])))
        for b in buckets {
            path.addLine(to: CGPoint(x: px(Double(b.minutesOfDay)), y: py(b[keyPath: top])))
        }
        for b in buckets.reversed() {
            path.addLine(to: CGPoint(x: px(Double(b.minutesOfDay)), y: py(b[keyPath: bottom])))
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(Theme.accent.opacity(opacity)))
    }

    private func yTicks(top: Double) -> [Double] {
        var ticks: [Double] = [thresholds.targetLower, thresholds.targetUpper]
        let capped = (top / 50).rounded(.down) * 50
        if capped > thresholds.targetUpper + 25 { ticks.append(capped) }
        return ticks
    }
}

#endif
