import SwiftUI
import WidgetKit
import Charts
import Foundation

/// The Home Screen glucose widget: small, medium, and large families rendered
/// entirely from a `GlucoseSnapshot`. No domain layer, no design components —
/// only the zone colour (`Color(hex:)`) crosses over from the app.
struct GlucoseWidget: Widget {
    let kind = "GlucoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseProvider()) { entry in
            GlucoseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Glucose")
        .description("Your latest glucose reading, trend, and recent history.")
        // .systemExtraLarge only ever appears on iPad — iPhone stops at Large.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

/// Routes each supported family to its layout and installs the shared widget
/// container background.
private struct GlucoseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                WidgetGlucoseSmall(snapshot: entry.snapshot)
            case .systemMedium:
                WidgetGlucoseMedium(snapshot: entry.snapshot)
            case .systemLarge:
                WidgetGlucoseLarge(snapshot: entry.snapshot)
            case .systemExtraLarge:
                WidgetGlucoseExtraLarge(snapshot: entry.snapshot)
            default:
                WidgetGlucoseSmall(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        // Tapping the widget opens the quick-entry hub to log a reading or entry.
        .widgetURL(URL(string: "prvital://log"))
    }
}

// MARK: - Small

private struct WidgetGlucoseSmall: View {
    let snapshot: GlucoseSnapshot
    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(snapshot.zoneLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(zoneColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: snapshot.trendSymbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(zoneColor)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.valueText)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.isStale ? Color.secondary : Color.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(snapshot.unitText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(zoneColor)
                    .frame(width: 6, height: 6)
                Text(snapshot.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if snapshot.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if snapshot.updatedAt > .distantPast {
                    Text(snapshot.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetSnapshotText.valueSummary(snapshot))
    }
}

// MARK: - Medium

private struct WidgetGlucoseMedium: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetGlucoseValueColumn(snapshot: snapshot)
                Spacer(minLength: 0)
                if let insulin = snapshot.lastInsulinText {
                    Label(insulin, systemImage: "syringe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("Last insulin \(insulin)")
                }
                WidgetOnBoardStrip(snapshot: snapshot)
                WidgetUpdatedText(snapshot: snapshot)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WidgetGlucoseChart(snapshot: snapshot)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Large

private struct WidgetGlucoseLarge: View {
    let snapshot: GlucoseSnapshot
    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                WidgetGlucoseValueColumn(snapshot: snapshot)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(zoneColor)
                            .frame(width: 6, height: 6)
                        Text(snapshot.sourceName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    WidgetUpdatedText(snapshot: snapshot)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            WidgetStatsRow(snapshot: snapshot)

            WidgetGlucoseChart(snapshot: snapshot, showsForecastBand: true)
                .frame(height: 122)

            // The forecast where you glance: an imminent low/high warning, shown
            // only when the app predicts one. Same neutral, triangle-marked
            // treatment as the Live Activity, so the prediction reads identically
            // on the Lock Screen banner, the Dynamic Island, and here.
            if let prediction = snapshot.predictionText {
                Label(prediction, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            WidgetOnBoardStrip(snapshot: snapshot)

            if let reminder = snapshot.nextReminderText {
                Label(reminder, systemImage: "bell.badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Next reminder \(reminder)")
            }

            if !snapshot.recentEntries.isEmpty {
                Divider().opacity(0.35)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(snapshot.recentEntries.prefix(4).enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 7) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.tertiary)
                            Text(entry)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recent entries")
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Extra large (iPad)

/// The extra-large family: a two-column dashboard-in-a-widget — the reading,
/// today's stats, therapy state and recent entries on the left, a big forecast
/// chart on the right. iPad-only by platform rule; iPhone stops at Large.
private struct WidgetGlucoseExtraLarge: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                WidgetGlucoseValueColumn(snapshot: snapshot)
                WidgetStatsRow(snapshot: snapshot)
                WidgetOnBoardStrip(snapshot: snapshot)
                if let prediction = snapshot.predictionText {
                    Label(prediction, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if !snapshot.recentEntries.isEmpty {
                    Divider().opacity(0.35)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(snapshot.recentEntries.prefix(5).enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 7) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(.tertiary)
                                Text(entry)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recent entries")
                }
                Spacer(minLength: 0)
                WidgetUpdatedText(snapshot: snapshot)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 270, alignment: .leading)

            WidgetGlucoseChart(snapshot: snapshot, showsForecastBand: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Today's stats row

/// "TIR 74% · Average 128" — today's headline figures, rendered from the
/// pre-formatted snapshot strings (no math runs in the widget process).
private struct WidgetStatsRow: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        if snapshot.todayTIRText != nil || snapshot.todayAverageText != nil {
            HStack(spacing: 16) {
                if let tir = snapshot.todayTIRText {
                    stat(label: String(localized: "TIR"), value: tir,
                         tint: Color(hex: 0x34D07A))
                }
                if let average = snapshot.todayAverageText {
                    stat(label: String(localized: "Average"), value: average,
                         tint: .primary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}

// MARK: - Shared value column

private struct WidgetGlucoseValueColumn: View {
    let snapshot: GlucoseSnapshot
    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.valueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.isStale ? Color.secondary : Color.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(snapshot.unitText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Image(systemName: snapshot.trendSymbol)
                    .font(.caption.weight(.bold))
                Text(snapshot.trendLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(zoneColor)

            Text(snapshot.zoneLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(zoneColor.opacity(0.9))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetSnapshotText.valueSummary(snapshot))
    }
}

// MARK: - On-board strip

/// A compact "on board" strip: insulin- and carbs-on-board chips, shown only when
/// the app supplied them. Mirrors the Live Activity / Dynamic Island and the Apple
/// Watch Now page so the same live therapy state — how much insulin is still
/// working and how many carbs are still digesting — reads identically on every
/// surface. Rendered from pre-formatted snapshot strings, so no medical logic runs
/// in the widget process.
private struct WidgetOnBoardStrip: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        if snapshot.iobText != nil || snapshot.cobText != nil {
            HStack(spacing: 12) {
                if let iob = snapshot.iobText {
                    Label(iob, systemImage: "syringe.fill")
                        .lineLimit(1)
                        .accessibilityLabel("Insulin on board \(iob)")
                }
                if let cob = snapshot.cobText {
                    Label(cob, systemImage: "fork.knife")
                        .lineLimit(1)
                        .accessibilityLabel("Carbs on board \(cob)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Chart

private struct WidgetGlucoseChart: View {
    let snapshot: GlucoseSnapshot
    /// Only the large family has the horizontal room to render the forecast's
    /// uncertainty cone; the medium chart is too narrow for it to read as anything
    /// but noise, so it shows just the central dashed tail.
    var showsForecastBand: Bool = false
    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    private var yDomain: ClosedRange<Double> {
        var values = snapshot.points.map(\.mgdL) + [snapshot.targetLowerMgdL, snapshot.targetUpperMgdL]
        if let forecast = snapshot.forecastMgdL { values.append(forecast) }
        if showsForecastBand {
            if let low = snapshot.forecastLowMgdL { values.append(low) }
            if let high = snapshot.forecastHighMgdL { values.append(high) }
        }
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return 40...200 }
        let pad = max((hi - lo) * 0.12, 8)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        if snapshot.points.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.secondary.opacity(0.08))
                Text("No recent data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        } else {
            Chart {
                RuleMark(y: .value("Upper target", snapshot.targetUpperMgdL))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("Lower target", snapshot.targetLowerMgdL))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(snapshot.points) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.mgdL)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [zoneColor.opacity(0.28), zoneColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.mgdL),
                        series: .value("Series", "history")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(zoneColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                if let last = snapshot.points.last {
                    // A soft "live" glow around the current reading. Home Screen
                    // widgets render as static timeline snapshots and can't run the
                    // app's repeating pulse, so two translucent halo rings layered
                    // under the solid dot stand in for it — the point still reads as
                    // the living "now", just without the motion.
                    PointMark(
                        x: .value("Time", last.date),
                        y: .value("Glucose", last.mgdL)
                    )
                    .foregroundStyle(zoneColor.opacity(0.14))
                    .symbolSize(230)
                    PointMark(
                        x: .value("Time", last.date),
                        y: .value("Glucose", last.mgdL)
                    )
                    .foregroundStyle(zoneColor.opacity(0.30))
                    .symbolSize(110)
                    PointMark(
                        x: .value("Time", last.date),
                        y: .value("Glucose", last.mgdL)
                    )
                    .foregroundStyle(zoneColor)
                    .symbolSize(34)
                }

                // The damped forecast as a dashed tail continuing past the last
                // reading, in its own series so it never merges with the history
                // line, plus a faint dot at the projected value. Shown only when
                // the app supplied a moving projection.
                if let forecastMgdL = snapshot.forecastMgdL,
                   let forecastAt = snapshot.forecastAt,
                   let last = snapshot.points.last {
                    ForEach([
                        GlucoseSnapshot.Point(date: last.date, mgdL: last.mgdL),
                        GlucoseSnapshot.Point(date: forecastAt, mgdL: forecastMgdL)
                    ]) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.mgdL),
                            series: .value("Series", "forecast")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(zoneColor.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }

                    PointMark(
                        x: .value("Time", forecastAt),
                        y: .value("Glucose", forecastMgdL)
                    )
                    .foregroundStyle(zoneColor.opacity(0.6))
                    .symbolSize(20)

                    // The honest uncertainty cone: faint bounds fanning from the
                    // last reading (zero spread) out to the projected low/high at
                    // the horizon. Large family only — see showsForecastBand.
                    if showsForecastBand,
                       let low = snapshot.forecastLowMgdL,
                       let high = snapshot.forecastHighMgdL {
                        ForEach([
                            GlucoseSnapshot.Point(date: last.date, mgdL: last.mgdL),
                            GlucoseSnapshot.Point(date: forecastAt, mgdL: low)
                        ]) { point in
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Glucose", point.mgdL),
                                series: .value("Series", "forecastLow")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(zoneColor.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        }
                        ForEach([
                            GlucoseSnapshot.Point(date: last.date, mgdL: last.mgdL),
                            GlucoseSnapshot.Point(date: forecastAt, mgdL: high)
                        ]) { point in
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Glucose", point.mgdL),
                                series: .value("Series", "forecastHigh")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(zoneColor.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityLabel("Glucose history, last \(snapshot.points.count) readings")
        }
    }
}

// MARK: - Updated caption

/// A self-updating "Updated N min ago" caption. `Text(_:style:.relative)` keeps
/// counting on its own without a timeline reload, so the widget always looks
/// live even between the app's snapshot republishes.
private struct WidgetUpdatedText: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        if snapshot.updatedAt > .distantPast {
            HStack(spacing: 3) {
                Text("Updated")
                Text(snapshot.updatedAt, style: .relative)
            }
            .lineLimit(1)
        } else {
            Text("No update")
        }
    }
}

// MARK: - Text helpers

/// Pre-composed strings for VoiceOver and captions, kept in one place so the
/// small/medium/large layouts stay in sync.
private enum WidgetSnapshotText {
    static func valueSummary(_ snapshot: GlucoseSnapshot) -> String {
        var summary = "\(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), \(snapshot.zoneLabel), from \(snapshot.sourceName)"
        if snapshot.isStale {
            summary += ", reading may be out of date"
        }
        return summary
    }
}
