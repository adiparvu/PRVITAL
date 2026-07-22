import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Your data. Shows how many records of each type live on the device, toggles
/// private iCloud sync, imports a CSV, exports a report, and offers an
/// irreversible "delete all" that removes every record through the single write
/// path. Export is also reachable from Insights (report beside the charts);
/// this second entry sits next to Import so the data in/out pair lives together.
/// Source access is revoked under Sources.
struct DataControlsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext

    // Counts come from `fetchCount` (a SQL COUNT) refreshed on appear and after
    // an import/delete — not an @Query that materialises every row — so opening
    // this screen right after a full-history import stays instant.
    @State private var counts = RecordCounts()

    @State private var showingDeleteConfirm = false
    @State private var showingImporter = false
    @State private var showingImportResult = false
    @State private var importResultMessage = ""
    @State private var isImporting = false

    private var totalCount: Int { counts.total }

    /// Per-type record counts, fetched cheaply without loading the rows.
    struct RecordCounts: Equatable {
        var glucose = 0, insulin = 0, carbs = 0, activity = 0, observations = 0
        var total: Int { glucose + insulin + carbs + activity + observations }
    }

    private func refreshCounts() {
        counts = RecordCounts(
            glucose: (try? modelContext.fetchCount(FetchDescriptor<GlucoseReading>())) ?? 0,
            insulin: (try? modelContext.fetchCount(FetchDescriptor<InsulinDose>())) ?? 0,
            carbs: (try? modelContext.fetchCount(FetchDescriptor<CarbEntry>())) ?? 0,
            activity: (try? modelContext.fetchCount(FetchDescriptor<ActivityEntry>())) ?? 0,
            observations: (try? modelContext.fetchCount(FetchDescriptor<ObservationEntry>())) ?? 0
        )
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
                    DataCountRow(title: "Glucose readings", systemImage: "drop.fill", tint: Theme.zoneInRange, count: counts.glucose)
                    DataCountRow(title: "Insulin doses", systemImage: "syringe.fill", tint: Theme.accent, count: counts.insulin)
                    DataCountRow(title: "Carb entries", systemImage: "fork.knife", tint: Theme.zoneHigh, count: counts.carbs)
                    DataCountRow(title: "Activities", systemImage: "figure.walk", tint: Theme.zoneWarning, count: counts.activity)
                    DataCountRow(title: "Observations", systemImage: "note.text", tint: Theme.textSecondary, count: counts.observations)
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("\(totalCount) records stored locally.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

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
            .glassListRow()

            Section {
                Button {
                    Haptics.play(.selection)
                    showingImporter = true
                } label: {
                    HStack {
                        Label {
                            Text("Import from file").foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "square.and.arrow.down").foregroundStyle(Theme.accent)
                        }
                        if isImporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting)
            } header: {
                Text("Import")
            } footer: {
                Text("Add records from a CSV file exported from Prvital, Dexcom Clarity or LibreView — including your full history. The format is detected automatically, and re-importing the same file won't create duplicates.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                NavigationLink {
                    ExportView()
                } label: {
                    Label {
                        Text("Export a report").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("A PDF report for your care team, or a CSV of your records, for a period you choose.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

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
            .glassListRow()

            Section {
                Label {
                    Text("Your records are health data. Handle exports and backups with the same care you'd give any medical information.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "heart.text.square").foregroundStyle(Theme.accent)
                }
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshCounts() }
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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            importResultMessage = String(localized: "Couldn't open that file.")
            showingImportResult = true
        case .success(let url):
            // Read the whole file into memory, then release the security-scoped
            // handle before the (potentially long) parse + import runs.
            let scoped = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                importResultMessage = String(localized: "Couldn't read that file.")
                showingImportResult = true
                return
            }
            isImporting = true
            Task {
                // Parse off the main actor — a full-history export is large — then
                // write through the batched, idempotent bulk-import path (which
                // dedups and resolves duplicate glucose readings).
                let parsed = await Task.detached { ExternalCSVImporter.parse(text) }.value
                guard let (format, result) = parsed else {
                    isImporting = false
                    Haptics.play(.warning)
                    importResultMessage = String(localized: "This file doesn't look like a Prvital, Dexcom Clarity or LibreView CSV export.")
                    showingImportResult = true
                    return
                }
                let summary = await env.entryStore.bulkImport(
                    result.rows, alreadySkipped: result.skipped)
                isImporting = false
                Haptics.play(summary.imported > 0 ? .success : .warning)
                importResultMessage = Self.resultMessage(for: summary, format: format)
                showingImportResult = true
                refreshCounts()
            }
        }
    }

    private static func resultMessage(for summary: ImportSummary, format: ExternalCSVFormat) -> String {
        var message = summary.imported == 1
            ? String(localized: "Imported \(summary.imported.formatted()) record from \(format.displayName).")
            : String(localized: "Imported \(summary.imported.formatted()) records from \(format.displayName).")
        if summary.duplicates > 0 {
            message += " " + String(localized: "\(summary.duplicates.formatted()) already imported.")
        }
        if summary.skipped > 0 {
            message += " " + (summary.skipped == 1
                ? String(localized: "Skipped \(summary.skipped.formatted()) row.")
                : String(localized: "Skipped \(summary.skipped.formatted()) rows."))
        }
        return message
    }

    private func deleteEverything() {
        Haptics.play(.warning)
        for record in (try? modelContext.fetch(FetchDescriptor<GlucoseReading>())) ?? [] { env.entryStore.delete(record) }
        for record in (try? modelContext.fetch(FetchDescriptor<InsulinDose>())) ?? [] { env.entryStore.delete(record) }
        for record in (try? modelContext.fetch(FetchDescriptor<CarbEntry>())) ?? [] { env.entryStore.delete(record) }
        for record in (try? modelContext.fetch(FetchDescriptor<ActivityEntry>())) ?? [] { env.entryStore.delete(record) }
        for record in (try? modelContext.fetch(FetchDescriptor<ObservationEntry>())) ?? [] { env.entryStore.delete(record) }
        refreshCounts()
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
