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

    /// Maps the journal's record arrays into a flat, chart-ready event list.
    static func build(
        insulin: [InsulinDose] = [],
        meals: [CarbEntry] = [],
        medications: [MedicationDose] = [],
        activity: [ActivityEntry] = [],
        ketones: [KetoneReading] = [],
        notes: [ObservationEntry] = []
    ) -> [ChartEvent] {
        var out: [ChartEvent] = []
        out += insulin.map { ChartEvent(id: "i-\($0.id)", date: $0.timestamp, kind: .insulin) }
        out += meals.map { ChartEvent(id: "m-\($0.id)", date: $0.timestamp, kind: .meal) }
        out += medications.map { ChartEvent(id: "d-\($0.id)", date: $0.timestamp, kind: .medication) }
        out += activity.map { ChartEvent(id: "a-\($0.id)", date: $0.startTimestamp, kind: .activity) }
        out += ketones.map { ChartEvent(id: "k-\($0.id)", date: $0.timestamp, kind: .ketone) }
        out += notes.map { ChartEvent(id: "n-\($0.id)", date: $0.timestamp, kind: .note) }
        return out
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
                .listRowBackground(Theme.surface)
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
