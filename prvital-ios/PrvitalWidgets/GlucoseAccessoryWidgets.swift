import SwiftUI
import WidgetKit
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
            Text(snapshot.unitText)
        } currentValueLabel: {
            Text(snapshot.valueText)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Color(hex: snapshot.zoneColorHex))
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel("Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.zoneLabel)")
    }
}

// MARK: - Rectangular

private struct WidgetAccessoryRectangular: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
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
            Text(snapshot.sourceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), from \(snapshot.sourceName)")
    }
}

// MARK: - Inline

private struct WidgetAccessoryInline: View {
    let snapshot: GlucoseSnapshot

    var body: some View {
        // Inline widgets render as a single Label beside the clock; the system
        // ignores custom backgrounds here.
        Label {
            Text("\(snapshot.valueText) \(snapshot.unitText)")
        } icon: {
            Image(systemName: snapshot.trendSymbol)
        }
        .accessibilityLabel("Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel)")
    }
}
