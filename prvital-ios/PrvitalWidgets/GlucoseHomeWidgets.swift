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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
            default:
                WidgetGlucoseSmall(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
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

            WidgetGlucoseChart(snapshot: snapshot)
                .frame(height: 110)

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

// MARK: - Chart

private struct WidgetGlucoseChart: View {
    let snapshot: GlucoseSnapshot
    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    private var yDomain: ClosedRange<Double> {
        let values = snapshot.points.map(\.mgdL) + [snapshot.targetLowerMgdL, snapshot.targetUpperMgdL]
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
                        y: .value("Glucose", point.mgdL)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(zoneColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                if let last = snapshot.points.last {
                    PointMark(
                        x: .value("Time", last.date),
                        y: .value("Glucose", last.mgdL)
                    )
                    .foregroundStyle(zoneColor)
                    .symbolSize(34)
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
