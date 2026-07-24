import SwiftUI

/// Press-down spring for tappable cards and large surfaces — a gentle 3% sink
/// that makes the whole app feel physical without stealing attention.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A tighter press style for chips and small controls.
struct PressableChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Coloured pill showing a glucose zone ("In range", "Low"…).
struct ZonePill: View {
    let zone: GlucoseZone
    /// When true, renders as plain tinted text with no filled capsule behind it.
    var plain: Bool = false

    var body: some View {
        let label = Text(zone.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(zone.color)
            .contentTransition(.opacity)
            .animation(.smooth, value: zone)
            .accessibilityLabel("Zone: \(zone.label)")
        if plain {
            label
        } else {
            label
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(zone.color.opacity(0.16), in: .capsule)
        }
    }
}

/// Trend arrow with an optional textual label.
struct TrendBadge: View {
    let trend: GlucoseTrend
    var showsLabel = false

    /// A fast move gets a warning tint; steady trends stay quiet.
    private var tint: Color {
        switch trend {
        case .fallingFast: return Theme.zoneCritical
        case .risingFast: return Theme.zoneHigh
        default: return Theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.symbol).font(.caption.weight(.bold))
            if showsLabel { Text(trend.label).font(.caption2.weight(.medium)) }
        }
        .foregroundStyle(tint)
        .animation(.smooth, value: trend)
        .accessibilityLabel("Trend: \(trend.label)")
    }
}

/// Source provenance chip ("Dexcom", "Apple Health"…).
struct ProvenanceBadge: View {
    let source: DataSource
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.symbol).font(.caption2.weight(.semibold))
            Text(source.displayName).font(.caption2.weight(.medium))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.hairline.opacity(0.5), in: .capsule)
        .accessibilityLabel("Source: \(source.displayName)")
    }
}

/// A compact statistic tile: value, caption, optional tint.
struct StatTile: View {
    /// Localized label (e.g. "Average"). `value`/`caption` are data shown verbatim.
    let title: LocalizedStringKey
    let value: String
    var caption: String?
    var tint: Color = Theme.accent
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.caption).foregroundStyle(tint) }
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            if let caption { Text(caption).font(.caption2).foregroundStyle(Theme.textTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        // Combine the (localized) label and the value/caption texts for VoiceOver.
        .accessibilityElement(children: .combine)
    }
}

/// A quick-add pill button (e.g. "+2 U", "40 g", "30 min").
struct QuickChip: View {
    let label: String
    var isSelected = false
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minWidth: 56, minHeight: 44) // meet the 44pt HIG tap-target minimum
                .background(isSelected ? tint : tint.opacity(0.12), in: .capsule)
                .foregroundStyle(isSelected ? Color.white : tint)
                .animation(.snappy, value: isSelected)
        }
        .buttonStyle(PressableChipStyle())
    }
}

/// Standard empty-state placeholder.
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accentSoft, in: .circle)
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text(title).font(.headline).foregroundStyle(Theme.textSecondary)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .appearTransition()
    }
}
