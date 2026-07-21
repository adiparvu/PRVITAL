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
            // When stale, show how old the value is (self-advancing relative
            // text) instead of the source — a frozen number must say so.
            if snapshot.isStale, snapshot.updatedAt > .distantPast {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(snapshot.updatedAt, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text(snapshot.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.isStale
            ? "Glucose \(snapshot.valueText) \(snapshot.unitText), outdated"
            : "Glucose \(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), from \(snapshot.sourceName)")
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
