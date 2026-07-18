import SwiftUI

/// Coloured pill showing a glucose zone ("In range", "Low"…).
struct ZonePill: View {
    let zone: GlucoseZone
    var body: some View {
        Text(zone.label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(zone.color.opacity(0.16), in: .capsule)
            .foregroundStyle(zone.color)
            .accessibilityLabel("Zone: \(zone.label)")
    }
}

/// Trend arrow with an optional textual label.
struct TrendBadge: View {
    let trend: GlucoseTrend
    var showsLabel = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.symbol).font(.system(size: 13, weight: .bold))
            if showsLabel { Text(trend.label).font(.system(size: 12, weight: .medium)) }
        }
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel("Trend: \(trend.label)")
    }
}

/// Source provenance chip ("Dexcom", "Apple Health"…).
struct ProvenanceBadge: View {
    let source: DataSource
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.symbol).font(.system(size: 11, weight: .semibold))
            Text(source.displayName).font(.system(size: 12, weight: .medium))
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
    let title: String
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(caption.map { ", \($0)" } ?? "")")
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
                .frame(minWidth: 56)
                .background(isSelected ? tint : tint.opacity(0.12), in: .capsule)
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
    }
}

/// Standard empty-state placeholder.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.headline).foregroundStyle(Theme.textSecondary)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
