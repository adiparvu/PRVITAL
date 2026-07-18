import SwiftUI
import Foundation

/// Root of the watch experience: a vertically-paged glance stack.
///
///   1. **Now** — the current glucose value, trend, zone and freshness.
///   2. **Insulin** — one-tap quick doses, confirmed before they are sent.
///   3. **Carbs** — one-tap quick carb amounts, confirmed before they are sent.
///
/// Everything renders from `model.snapshot`; quick entries are handed to the
/// phone through `WatchSessionManager`, which logs them via the normal audited
/// entry path. Reading `model.snapshot` inside `body` is enough for the
/// `@Observable` model to keep every page live.
struct WatchRootView: View {
    let model: WatchModel

    var body: some View {
        TabView {
            WatchNowPage(snapshot: model.snapshot)

            WatchQuickEntryPage(
                title: "Insulin",
                systemImage: "syringe",
                kind: "insulin",
                unit: "U",
                values: [1, 2, 4, 6],
                tint: Theme.accent
            )

            WatchQuickEntryPage(
                title: "Carbs",
                systemImage: "fork.knife",
                kind: "carbs",
                unit: "g",
                values: [20, 40, 60],
                tint: Theme.zoneHigh
            )
        }
        .tabViewStyle(.verticalPage)
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Page 1 · Current glucose

/// The primary glance: a zone-coloured gauge ring around the current value,
/// with trend, zone label, source and time since the last update. When the
/// reading is stale the whole page is dimmed and a clock badge appears.
private struct WatchNowPage: View {
    let snapshot: GlucoseSnapshot

    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    /// Where the current value sits on a fixed 40–300 mg/dL display sweep,
    /// clamped to the ring. Drives the trimmed arc for a gauge feel.
    private var gaugeFraction: Double {
        let lower = 40.0
        let upper = 300.0
        return min(max((snapshot.mgdL - lower) / (upper - lower), 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(zoneColor.opacity(0.22), style: StrokeStyle(lineWidth: 9))

                Circle()
                    .trim(from: 0, to: max(gaugeFraction, 0.001))
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: snapshot.trendSymbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(zoneColor)

                    Text(snapshot.valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(snapshot.unitText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 122, height: 122)

            Text(snapshot.zoneLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(zoneColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(zoneColor.opacity(0.18), in: Capsule())

            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(zoneColor)
                        .frame(width: 5, height: 5)
                    Text(snapshot.sourceName)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if snapshot.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.zoneWarning)
                    }
                }
                Text(WatchSnapshotFormat.updated(snapshot.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(snapshot.isStale ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchSnapshotFormat.valueSummary(snapshot))
    }
}

// MARK: - Pages 2 & 3 · Quick entry

/// A reusable quick-entry glance shared by the insulin and carb pages. Each
/// amount is a large tap target; tapping it asks for confirmation first (a
/// safeguard for logging medication from the wrist) and, once confirmed, sends
/// the entry to the phone and shows a brief acknowledgement.
private struct WatchQuickEntryPage: View {
    let title: String
    let systemImage: String
    /// "insulin" or "carbs" — matches `WatchSessionManager.sendQuickEntry`.
    let kind: String
    /// Unit suffix shown on each button ("U" or "g").
    let unit: String
    let values: [Double]
    let tint: Color

    @State private var pending: Double?
    @State private var confirmation: WatchLogConfirmation?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        pending = value
                    } label: {
                        VStack(spacing: 1) {
                            Text(WatchSnapshotFormat.amount(value))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            Text(unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(WatchSnapshotFormat.amount(value)) \(WatchSnapshotFormat.unitName(unit))")
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let confirmation {
                Label("Logged \(WatchSnapshotFormat.amount(confirmation.amount)) \(unit)", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.zoneInRange.opacity(0.9), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: confirmation)
        .confirmationDialog(
            "Log \(WatchSnapshotFormat.amount(pending ?? 0)) \(unit)?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { value in
            Button("Log \(WatchSnapshotFormat.amount(value)) \(unit)") { commit(value) }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .task(id: confirmation?.id) {
            guard confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            confirmation = nil
        }
    }

    private func commit(_ value: Double) {
        WatchSessionManager.shared.sendQuickEntry(kind: kind, amount: value)
        pending = nil
        confirmation = WatchLogConfirmation(amount: value)
    }
}

/// A single "just logged" acknowledgement. The `id` makes repeated identical
/// amounts still re-trigger the auto-dismiss timer.
private struct WatchLogConfirmation: Equatable {
    let id = UUID()
    let amount: Double
}

// MARK: - Formatting helpers

/// Small formatting helpers shared by the watch pages. Kept in one place so the
/// glance and quick-entry pages phrase values and times identically.
private enum WatchSnapshotFormat {
    /// Whole numbers render without a decimal; fractions keep one place.
    static func amount(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Spoken form of a unit suffix for VoiceOver.
    static func unitName(_ unit: String) -> String {
        switch unit {
        case "U": return "units"
        case "g": return "grams"
        default: return unit
        }
    }

    /// "Updated 3 min ago", or a friendly fallback when there is no reading yet.
    static func updated(_ date: Date) -> String {
        guard date > .distantPast else { return "No recent data" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: date, relativeTo: Date())
    }

    static func valueSummary(_ snapshot: GlucoseSnapshot) -> String {
        var summary = "\(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), \(snapshot.zoneLabel), from \(snapshot.sourceName)"
        if snapshot.isStale {
            summary += ", reading may be out of date"
        }
        return summary
    }
}
