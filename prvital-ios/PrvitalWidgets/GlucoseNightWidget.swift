import SwiftUI
import WidgetKit

/// The bedside widget: built for StandBy (iPhone charging on its side at
/// night). One huge number in warm red on black — the palette night vision
/// keeps — with the trend arrow and the reading's age. Nothing else: at 3 AM,
/// at arm's length, with half-open eyes, the number IS the interface.
struct GlucoseNightWidget: Widget {
    let kind = "GlucoseNightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseProvider()) { entry in
            NightWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Night glance")
        .description("A huge, night-friendly reading for StandBy on your nightstand.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NightWidgetView: View {
    let snapshot: GlucoseSnapshot
    @Environment(\.widgetFamily) private var family

    /// Warm red holds night vision; out-of-range dims to amber for LOW so the
    /// colour itself says "look properly".
    private var tint: Color {
        snapshot.isStale ? Color(white: 0.55) : Color(red: 1.0, green: 0.27, blue: 0.23)
    }

    var body: some View {
        VStack(spacing: family == .systemMedium ? 6 : 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.valueText)
                    .font(.system(size: family == .systemMedium ? 76 : 52,
                                  weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !snapshot.isStale {
                    Image(systemName: snapshot.trendSymbol)
                        .font(.system(size: family == .systemMedium ? 30 : 20, weight: .bold))
                }
            }
            HStack(spacing: 6) {
                Text(snapshot.unitText)
                Text("·")
                Text(snapshot.updatedAt, style: .relative)
            }
            .font(.caption.weight(.medium))
            .opacity(0.7)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "prvital://log"))
        .accessibilityLabel("Glucose \(snapshot.valueText) \(snapshot.unitText)")
    }
}
