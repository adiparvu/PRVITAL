import SwiftUI

/// A kind of non-glucose event that can be pinned onto the glucose chart as a
/// small coloured marker. Each has a distinct SF Symbol and colour, and the user
/// chooses which kinds appear via `Preferences.chartEventKinds` (toggled from the
/// chart's ⓘ legend).
enum ChartEventKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case insulin, meal, medication, activity, ketone, note

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .insulin:    return "syringe.fill"
        case .meal:       return "fork.knife"
        case .medication: return "pills.fill"
        case .activity:   return "figure.walk"
        case .ketone:     return "drop.triangle.fill"
        case .note:       return "note.text"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .insulin:    return "Insulin"
        case .meal:       return "Meals"
        case .medication: return "Medications"
        case .activity:   return "Activity"
        case .ketone:     return "Ketones"
        case .note:       return "Notes"
        }
    }

    var color: Color {
        switch self {
        case .insulin:    return Theme.accent
        case .meal:       return Theme.zoneHigh
        case .medication: return Color(hex: 0x8E7CFF)   // a distinct violet
        case .activity:   return Theme.zoneInRange
        case .ketone:     return Theme.zoneCritical
        case .note:       return Theme.textSecondary
        }
    }

    /// Every kind shown by default (a fresh install marks everything).
    static var allShown: Set<ChartEventKind> { Set(allCases) }
}

/// A single event to draw on the chart: a time and its kind. Built from the
/// journal's records for the chart's window.
struct ChartEvent: Identifiable {
    let id: String
    let date: Date
    let kind: ChartEventKind
    /// The headline figure for the long-press detail sheet ("50 g", "4 U").
    var valueText: String?
    /// Supporting context ("Lunch · Pizza", the note's text, "45 min · Moderate").
    var detailText: String?

    /// Maps the journal's record arrays into a flat, chart-ready event list,
    /// carrying enough display-ready text that a marker can explain itself.
    static func build(
        insulin: [InsulinDose] = [],
        meals: [CarbEntry] = [],
        medications: [MedicationDose] = [],
        activity: [ActivityEntry] = [],
        ketones: [KetoneReading] = [],
        notes: [ObservationEntry] = []
    ) -> [ChartEvent] {
        var out: [ChartEvent] = []
        out += insulin.map { dose in
            ChartEvent(id: "i-\(dose.id)", date: dose.timestamp, kind: .insulin,
                       valueText: String(localized: "\(dose.units.formatted()) U"),
                       detailText: join(dose.insulinName ?? dose.insulinType.label, dose.note))
        }
        out += meals.map { meal in
            ChartEvent(id: "m-\(meal.id)", date: meal.timestamp, kind: .meal,
                       valueText: String(localized: "\(meal.grams.formatted()) g"),
                       detailText: join(meal.mealType.label, meal.foodDescription, meal.note))
        }
        out += medications.map { med in
            ChartEvent(id: "d-\(med.id)", date: med.timestamp, kind: .medication,
                       valueText: med.name.isEmpty ? nil : med.name,
                       detailText: join(med.amount > 0 ? "\(med.amount.formatted()) \(med.unitText)" : nil, med.note))
        }
        out += activity.map { entry in
            ChartEvent(id: "a-\(entry.id)", date: entry.startTimestamp, kind: .activity,
                       valueText: entry.activityType.label,
                       detailText: join(entry.durationSeconds > 0
                                            ? String(localized: "\(entry.durationSeconds / 60) min") : nil,
                                        entry.note))
        }
        out += ketones.map { reading in
            ChartEvent(id: "k-\(reading.id)", date: reading.timestamp, kind: .ketone,
                       valueText: "\(reading.value.formatted()) mmol/L",
                       detailText: join(reading.sample.label, reading.note))
        }
        out += notes.map { note in
            ChartEvent(id: "n-\(note.id)", date: note.timestamp, kind: .note,
                       valueText: nil,
                       detailText: note.text)
        }
        return out
    }

    private static func join(_ parts: String?...) -> String? {
        let text = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

/// What a long-press on an event marker opens: the action behind the icon,
/// spelled out — kind, exact time, headline figure and any description/note.
/// A read-only card, deliberately small (editing stays in the Journal).
struct ChartEventDetailSheet: View {
    let event: ChartEvent
    @Environment(\.dismiss) private var dismiss

    /// Singular title per kind (the legend's labels are plural categories).
    private var title: LocalizedStringKey {
        switch event.kind {
        case .insulin:    return "Insulin"
        case .meal:       return "Meal"
        case .medication: return "Medication"
        case .activity:   return "Activity"
        case .ketone:     return "Ketones"
        case .note:       return "Observation"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.textTertiary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            Image(systemName: event.kind.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(event.kind.color, in: .circle)
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(event.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let valueText = event.valueText {
                Text(valueText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(event.kind.color)
            }
            if let detailText = event.detailText {
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(300)])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.hidden)
    }
}

/// The ⓘ legend + show/hide toggles, presented from the chart. Reads and writes
/// the shared visibility set so a choice sticks across the app.
struct ChartEventLegend: View {
    @Binding var visible: Set<ChartEventKind>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ChartEventKind.allCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            Label {
                                Text(kind.label).foregroundStyle(Theme.textPrimary)
                            } icon: {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(kind.color, in: .circle)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } header: {
                    Text("Show on chart")
                } footer: {
                    Text("Pick which events appear as markers on the glucose chart. Each has its own colour and symbol.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("Chart markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(for kind: ChartEventKind) -> Binding<Bool> {
        Binding(
            get: { visible.contains(kind) },
            set: { on in
                Haptics.play(.selection)
                if on { visible.insert(kind) } else { visible.remove(kind) }
            }
        )
    }
}
