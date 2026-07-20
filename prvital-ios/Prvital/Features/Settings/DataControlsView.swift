import SwiftUI
import SwiftData

/// Your data. Shows how many records of each type live on the device, toggles
/// private iCloud sync, and offers an irreversible "delete all" that removes
/// every record through the single write path. Source access is revoked under
/// Sources; export lives under Insights.
struct DataControlsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]

    @State private var showingDeleteConfirm = false

    private var totalCount: Int {
        glucose.count + insulin.count + carbs.count + activity.count + observations.count
    }

    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { env.consent.isGranted(.cloudSync) },
            set: { granted in
                Haptics.play(.selection)
                env.consent.setGranted(.cloudSync, granted)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                if totalCount == 0 {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "No data yet",
                        message: "Readings and entries you log will appear here."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    DataCountRow(title: "Glucose readings", systemImage: "drop.fill", tint: Theme.zoneInRange, count: glucose.count)
                    DataCountRow(title: "Insulin doses", systemImage: "syringe.fill", tint: Theme.accent, count: insulin.count)
                    DataCountRow(title: "Carb entries", systemImage: "fork.knife", tint: Theme.zoneHigh, count: carbs.count)
                    DataCountRow(title: "Activities", systemImage: "figure.walk", tint: Theme.zoneWarning, count: activity.count)
                    DataCountRow(title: "Observations", systemImage: "note.text", tint: Theme.textSecondary, count: observations.count)
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("\(totalCount) records stored locally.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: cloudSyncBinding) {
                    Label {
                        Text("iCloud sync").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "icloud").foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("When on, your journal syncs across your devices through your own private iCloud database. Apple cannot read the contents.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Button(role: .destructive) {
                    Haptics.play(.warning)
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete all local data", systemImage: "trash.fill")
                }
                .disabled(totalCount == 0)
            } footer: {
                Text("This permanently removes every glucose, insulin, meal, activity and observation record from this device. It cannot be undone. To disconnect a source, use Sources; to export a report, use Insights.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Label {
                    Text("Your records are health data. Handle exports and backups with the same care you'd give any medical information.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "heart.text.square").foregroundStyle(Theme.accent)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete all local data?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(totalCount) records", role: .destructive) {
                deleteEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every record on this device will be permanently removed. This cannot be undone.")
        }
    }

    private func deleteEverything() {
        Haptics.play(.warning)
        for record in glucose { env.entryStore.delete(record) }
        for record in insulin { env.entryStore.delete(record) }
        for record in carbs { env.entryStore.delete(record) }
        for record in activity { env.entryStore.delete(record) }
        for record in observations { env.entryStore.delete(record) }
    }
}

// MARK: - Private helpers

/// A record-count row: tinted glyph, label and a rounded numeral count.
private struct DataCountRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Spacer()
            Text(count.formatted())
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count)")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { DataControlsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
