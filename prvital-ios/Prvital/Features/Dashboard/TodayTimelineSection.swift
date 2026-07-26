import SwiftUI

/// One logged event in today's timeline — a tinted glyph, a time, a title and an
/// optional detail line. Built from the day's records, not the CGM stream.
struct TodayEvent: Identifiable {
    let id: String
    let date: Date
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
}

/// The dashboard's "Today" timeline: the day's logged events — insulin, carbs,
/// activity, medication, ketones, notes and manual glucose — in one
/// chronological list, newest first. It's the story of the day at a glance.
/// Empty days stay quiet (the card hides itself), keeping the dashboard calm.
struct TodayTimelineCard: View {
    /// Precomputed by the parent (via `events(...)`) so it can test emptiness
    /// before composing the day's fused card.
    let events: [TodayEvent]
    /// When true, renders only the rows — the parent supplies the card chrome.
    var embedded = false

    private static let cap = 12

    var body: some View {
        if !events.isEmpty {
            if embedded {
                rows
            } else {
                SectionCard("Today", systemImage: "list.bullet.rectangle") { rows }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.prefix(Self.cap).enumerated()), id: \.element.id) { index, event in
                if index > 0 { Divider().overlay(Theme.hairline) }
                TodayEventRow(event: event)
            }
        }
    }

    static func events(
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        medications: [MedicationDose],
        ketones: [KetoneReading],
        notes: [ObservationEntry],
        unit: GlucoseUnit,
        thresholds: GlucoseThresholds
    ) -> [TodayEvent] {
        let cal = Calendar.current
        func isToday(_ date: Date) -> Bool { cal.isDateInToday(date) }
        var out: [TodayEvent] = []

        for d in insulin where isToday(d.timestamp) {
            out.append(TodayEvent(
                id: "i-\(d.id)", date: d.timestamp, icon: "syringe.fill", tint: Theme.accent,
                title: String(localized: "\(d.units.formatted()) U"), detail: d.insulinType.label))
        }
        for m in carbs where isToday(m.timestamp) {
            out.append(TodayEvent(
                id: "c-\(m.id)", date: m.timestamp, icon: "fork.knife", tint: Theme.zoneHigh,
                title: String(localized: "\(m.grams.formatted()) g"),
                detail: m.foodDescription ?? m.mealType.label))
        }
        for a in activity where isToday(a.startTimestamp) {
            out.append(TodayEvent(
                id: "a-\(a.id)", date: a.startTimestamp, icon: "figure.walk", tint: Theme.zoneInRange,
                title: String(localized: "\(a.durationMinutes) min"), detail: a.activityType.label))
        }
        for med in medications where isToday(med.timestamp) {
            out.append(TodayEvent(
                id: "d-\(med.id)", date: med.timestamp, icon: "pills.fill", tint: Theme.accent,
                title: med.name.isEmpty ? String(localized: "Medication") : med.name,
                detail: med.doseText.isEmpty ? nil : med.doseText))
        }
        for k in ketones where isToday(k.timestamp) {
            out.append(TodayEvent(
                id: "k-\(k.id)", date: k.timestamp, icon: "drop.triangle.fill", tint: Theme.zoneWarning,
                title: "\(k.value.formatted(.number.precision(.fractionLength(1)))) mmol/L",
                detail: String(localized: "Ketones")))
        }
        for n in notes where isToday(n.timestamp) {
            out.append(TodayEvent(
                id: "n-\(n.id)", date: n.timestamp, icon: "note.text", tint: Theme.textSecondary,
                title: n.text?.isEmpty == false ? n.text! : String(localized: "Note"), detail: nil))
        }
        // Manual glucose logs only — the CGM stream is what the trend chart shows.
        for r in readings where isToday(r.timestamp) && r.isActive && !r.source.isCGM {
            out.append(TodayEvent(
                id: "g-\(r.id)", date: r.timestamp, icon: "drop.fill",
                tint: thresholds.zone(forMgdL: r.valueMgdL).color,
                title: GlucoseFormatting.labeled(mgdL: r.valueMgdL, unit: unit),
                detail: r.source.displayName))
        }

        return out.sorted { $0.date > $1.date }
    }
}

private struct TodayEventRow: View {
    let event: TodayEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(event.tint, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(event.date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.date.formatted(date: .omitted, time: .shortened))")
    }
}
