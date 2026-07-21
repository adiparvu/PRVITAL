import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Timeline model

/// A single, source-agnostic row on the journal / history timeline.
///
/// Every medical record — glucose, insulin, carbs, activity, observation — is
/// projected into this uniform value type so the Journal and History screens can
/// render one heterogeneous, chronologically sorted list. The concrete model is
/// kept alongside the row so tapping can hand the exact record to its editor.
struct JournalTimelineItem: Identifiable {
    /// Which record family this row represents.
    enum Kind: String, CaseIterable, Sendable {
        case glucose, insulin, carbs, activity, observation
    }

    let id: UUID
    let date: Date
    let kind: Kind

    // Exactly one of these is non-nil, matching `kind`.
    var glucose: GlucoseReading?
    var insulin: InsulinDose?
    var carbs: CarbEntry?
    var activity: ActivityEntry?
    var observation: ObservationEntry?

    /// Provenance of the underlying record (drives the ProvenanceBadge).
    var source: DataSource {
        glucose?.source
            ?? insulin?.source
            ?? carbs?.source
            ?? activity?.source
            ?? observation?.source
            ?? .manual
    }

    /// Builds a flat, unsorted list of timeline items from the five record
    /// collections. Only *active* glucose readings are included so losing sides
    /// of a resolved conflict never surface. Callers sort as they see fit.
    static func build(
        glucose: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        observations: [ObservationEntry]
    ) -> [JournalTimelineItem] {
        var items: [JournalTimelineItem] = []
        items.reserveCapacity(glucose.count + insulin.count + carbs.count + activity.count + observations.count)

        for reading in glucose where reading.isActive {
            items.append(JournalTimelineItem(id: reading.id, date: reading.timestamp, kind: .glucose, glucose: reading))
        }
        for dose in insulin {
            items.append(JournalTimelineItem(id: dose.id, date: dose.timestamp, kind: .insulin, insulin: dose))
        }
        for entry in carbs {
            items.append(JournalTimelineItem(id: entry.id, date: entry.timestamp, kind: .carbs, carbs: entry))
        }
        for entry in activity {
            items.append(JournalTimelineItem(id: entry.id, date: entry.startTimestamp, kind: .activity, activity: entry))
        }
        for entry in observations {
            items.append(JournalTimelineItem(id: entry.id, date: entry.timestamp, kind: .observation, observation: entry))
        }
        return items
    }
}

// MARK: - Timeline row

/// A single timeline row: a tinted icon, a title, a secondary detail line and a
/// trailing time. Glucose rows additionally show the numeric value with a
/// `ZonePill` and trend, and any non-manual source shows a `ProvenanceBadge`.
/// The row is presentation-only — tapping is handled by the containing screen.
struct JournalEntryRow: View {
    let item: JournalTimelineItem
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(Theme.textPrimary)
                    if let zone {
                        ZonePill(zone: zone)
                    }
                    if let trend {
                        TrendBadge(trend: trend)
                    }
                }
                if hasSecondaryLine {
                    HStack(spacing: 8) {
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if item.source != .manual {
                            ProvenanceBadge(source: item.source)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            carbThumbnail
            Text(timeText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Derived presentation

    /// A small rounded thumbnail for carb rows that carry a meal photo.
    @ViewBuilder
    private var carbThumbnail: some View {
        #if canImport(UIKit)
        if item.kind == .carbs, let data = item.carbs?.photo, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }

    private var icon: some View {
        // Per device feedback: the tinted icon stands on its own — no colour
        // chip behind it. The fixed frame keeps every row's text aligned.
        Image(systemName: symbolName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
    }

    private var symbolName: String {
        switch item.kind {
        case .glucose: return "drop.fill"
        case .insulin: return "syringe.fill"
        case .carbs: return item.carbs?.mealType.symbol ?? "fork.knife"
        case .activity: return item.activity?.activityType.symbol ?? "figure.walk"
        case .observation: return item.observation?.tags.first?.symbol ?? "note.text"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .glucose: return zone?.color ?? Theme.zoneCritical
        case .insulin: return Theme.accent
        case .carbs: return Theme.zoneHigh
        case .activity: return Theme.zoneInRange
        case .observation: return Theme.textSecondary
        }
    }

    private var zone: GlucoseZone? {
        guard let reading = item.glucose else { return nil }
        return thresholds.zone(forMgdL: reading.valueMgdL)
    }

    private var trend: GlucoseTrend? { item.glucose?.trend }

    private var title: String {
        switch item.kind {
        case .glucose:
            guard let reading = item.glucose else { return "" }
            return GlucoseFormatting.labeled(mgdL: reading.valueMgdL, unit: unit)
        case .insulin:
            guard let dose = item.insulin else { return "" }
            return String(localized: "\(dose.units.formatted()) U")
        case .carbs:
            guard let entry = item.carbs else { return "" }
            return String(localized: "\(entry.grams.formatted()) g")
        case .activity:
            return item.activity?.activityType.label ?? String(localized: "Activity")
        case .observation:
            return item.observation?.tags.first?.label ?? String(localized: "Note")
        }
    }

    /// Values use rounded numerals; textual titles use the default design.
    private var titleFont: Font {
        switch item.kind {
        case .glucose, .insulin, .carbs:
            return .system(.headline, design: .rounded)
        case .activity, .observation:
            return .headline
        }
    }

    private var detail: String {
        switch item.kind {
        case .glucose:
            return item.glucose?.measurementType.label ?? ""
        case .insulin:
            guard let dose = item.insulin else { return "" }
            var parts = [dose.doseContext.label, dose.insulinType.label]
            if let name = dose.insulinName, !name.isEmpty { parts.append(name) }
            return parts.joined(separator: " · ")
        case .carbs:
            guard let entry = item.carbs else { return "" }
            if let food = entry.foodDescription, !food.isEmpty {
                return "\(entry.mealType.label) · \(food)"
            }
            return entry.mealType.label
        case .activity:
            guard let entry = item.activity else { return "" }
            return String(localized: "\(entry.durationMinutes) min · \(entry.intensity.label)")
        case .observation:
            guard let entry = item.observation else { return "" }
            if let text = entry.text, !text.isEmpty { return text }
            return entry.tags.map(\.label).joined(separator: ", ")
        }
    }

    private var hasSecondaryLine: Bool {
        !detail.isEmpty || item.source != .manual
    }

    private var timeText: String {
        item.date.formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityText: String {
        var parts: [String] = [title]
        if let zone { parts.append("zone \(zone.label)") }
        if let trend { parts.append("trend \(trend.label)") }
        if !detail.isEmpty { parts.append(detail) }
        parts.append("at \(timeText)")
        if item.source != .manual { parts.append("from \(item.source.displayName)") }
        return parts.joined(separator: ", ")
    }
}
