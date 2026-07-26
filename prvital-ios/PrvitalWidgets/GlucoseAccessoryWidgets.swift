import SwiftUI
import WidgetKit
import Charts
import Foundation

/// Lock Screen / StandBy accessory glucose widget: circular, rectangular, and
/// inline families. Like the Home Screen widget it renders purely from a
/// `GlucoseSnapshot`; the system applies its own vibrant rendering mode, so the
/// zone tint is a hint rather than a guarantee.
struct GlucoseAccessoryWidget: Widget {
    let kind = "GlucoseAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseProvider()) { entry in
            GlucoseAccessoryEntryView(entry: entry)
        }
        .configurationDisplayName("Glucose")
        .description("Glucose value and trend at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct GlucoseAccessoryEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            WidgetAccessoryCircular(snapshot: entry.snapshot)
        case .accessoryRectangular:
            WidgetAccessoryRectangular(snapshot: entry.snapshot)
        case .accessoryInline:
            WidgetAccessoryInline(snapshot: entry.snapshot)
        default:
            WidgetAccessoryRectangular(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Circular

private struct WidgetAccessoryCircular: View {
    let snapshot: GlucoseSnapshot

    /// Normalise the reading into a 40–300 mg/dL display window for the ring fill.
    private var fraction: Double {
        let clamped = min(max(snapshot.mgdL, 40), 300)
        return (clamped - 40) / (300 - 40)
    }

    var body: some View {
        Gauge(value: fraction) {
            // When the reading is stale, swap the unit for a clock so a frozen
            // number is visibly out of date even in this tiny family.
            if snapshot.isStale {
                Image(systemName: "clock")
            } else {
                Text(snapshot.unitText)
            }
        } currentValueLabel: {
            Text(snapshot.valueText)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .opacity(snapshot.isStale ? 0.55 : 1)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(snapshot.isStale ? Color.gray : Color(hex: snapshot.zoneColorHex))
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(snapshot.isStale
            ? "Glucose \(snapshot.valueText) \(snapshot.unitText), outdated"
            : "Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.zoneLabel)")
    }
}

// MARK: - Rectangular

private struct WidgetAccessoryRectangular: View {
    let snapshot: GlucoseSnapshot

    /// The last ~2 hours as a tiny sparkline beside the value — the watch
    /// complication finally shows the *shape* of the trend, not just a number.
    private var sparkPoints: [GlucoseSnapshot.Point] {
        Array(snapshot.points.suffix(24))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.valueText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(snapshot.unitText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: snapshot.trendSymbol)
                    .font(.footnote.weight(.bold))
                    .imageScale(.small)
            }
            // Second line, in priority order:
            //  • stale → how old the value is (a frozen number must say so);
            //  • an imminent low/high → the forecast warning, the most important
            //    thing to glance at on a watch face / Lock Screen;
            //  • otherwise → the source.
            if snapshot.isStale, snapshot.updatedAt > .distantPast {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(snapshot.updatedAt, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let prediction = snapshot.predictionText {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(prediction)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(snapshot.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        if sparkPoints.count >= 3 {
            Chart(sparkPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Glucose", point.mgdL)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: 52, height: 30)
            .accessibilityHidden(true)
        }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if snapshot.isStale {
            return "Glucose \(snapshot.valueText) \(snapshot.unitText), outdated"
        }
        if let prediction = snapshot.predictionText {
            return "Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), \(prediction)"
        }
        return "Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), from \(snapshot.sourceName)"
    }
}

// MARK: - Inline

private struct WidgetAccessoryInline: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        // Inline widgets render as a single Label beside the clock; the system
        // ignores custom backgrounds here. A stale value swaps the trend arrow
        // for a clock so it can't pass for a live reading.
        Label {
            Text("\(snapshot.valueText) \(snapshot.unitText)")
        } icon: {
            Image(systemName: snapshot.isStale ? "clock" : snapshot.trendSymbol)
        }
        .accessibilityLabel(snapshot.isStale
            ? "Glucose \(snapshot.valueText) \(snapshot.unitText), outdated"
            : "Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel)")
    }
}
