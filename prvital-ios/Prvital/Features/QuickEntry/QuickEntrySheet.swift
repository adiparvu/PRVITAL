import SwiftUI

/// Identifies which full editor to present. Public so any screen can drive an
/// editor sheet with `.sheet(item:)`.
enum EntryEditorKind: String, Identifiable {
    case glucose, insulin, carbs, activity, observation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .glucose: return "Glucose"
        case .insulin: return "Insulin"
        case .carbs: return "Carbs"
        case .activity: return "Activity"
        case .observation: return "Observation"
        }
    }
    var symbol: String {
        switch self {
        case .glucose: return "drop.fill"
        case .insulin: return "syringe.fill"
        case .carbs: return "fork.knife"
        case .activity: return "figure.walk"
        case .observation: return "note.text"
        }
    }
    var tint: Color {
        switch self {
        case .glucose: return Theme.zoneCritical
        case .insulin: return Theme.accent
        case .carbs: return Theme.zoneHigh
        case .activity: return Theme.zoneInRange
        case .observation: return Theme.textSecondary
        }
    }
}

/// Presents the editor for a given kind. Reused by Dashboard, Journal and
/// History so editing is identical everywhere.
struct EntryEditor: View {
    let kind: EntryEditorKind
    var body: some View {
        switch kind {
        case .glucose: GlucoseEntrySheet()
        case .insulin: InsulinEntrySheet()
        case .carbs: CarbEntrySheet()
        case .activity: ActivityEntrySheet()
        case .observation: ObservationEntrySheet()
        }
    }
}

/// The quick-entry hub: fast one-tap insulin / carb chips plus a launcher grid
/// into the full editors.
struct QuickEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EntryEditorKind?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SectionCard("Quick insulin", systemImage: "syringe.fill") {
                        chipRow(env.preferences.insulinPresets.map { ("+\($0.formatted()) U", $0) }, tint: Theme.accent) { units in
                            env.entryStore.addInsulin(units: units)
                            Haptics.play(.success); dismiss()
                        }
                    }
                    .appearTransition(delay: 0)
                    SectionCard("Quick carbs", systemImage: "fork.knife") {
                        chipRow(env.preferences.carbPresets.map { ("\($0.formatted()) g", $0) }, tint: Theme.zoneHigh) { grams in
                            env.entryStore.addCarbs(grams: grams)
                            Haptics.play(.success); dismiss()
                        }
                    }
                    .appearTransition(delay: 0.06)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array([EntryEditorKind.glucose, .insulin, .carbs, .activity, .observation].enumerated()), id: \.element) { index, kind in
                            Button { editor = kind } label: { launcherTile(kind) }
                                .buttonStyle(.plain)
                                .appearTransition(delay: 0.12 + Double(index) * 0.05)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Add entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editor) { EntryEditor(kind: $0) }
        }
    }

    private func chipRow(_ items: [(String, Double)], tint: Color, action: @escaping (Double) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    QuickChip(label: item.0, tint: tint) { action(item.1) }
                }
            }
        }
    }

    private func launcherTile(_ kind: EntryEditorKind) -> some View {
        VStack(spacing: 8) {
            Image(systemName: kind.symbol).font(.title2).foregroundStyle(kind.tint)
            Text(kind.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .glassCard(cornerRadius: 18, padding: 8)
    }
}
