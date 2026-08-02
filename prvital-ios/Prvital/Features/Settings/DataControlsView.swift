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
    // Full-journal JSON backup: the written file to share, and restore state.
    @State private var backupFileURL: URL?
    @State private var isExportingBackup = false
    @State private var showingRestorePicker = false
    @State private var isRestoring = false
    /// Whether the onboarding demo week is still in the store.
    @State private var hasDemoData = DemoDataSeeder.hasDemoData

    // Past imports, newest first — each removable as a unit (undo a wrong file).
    @Query(sort: \ImportBatch.importedAt, order: .reverse) private var importBatches: [ImportBatch]
    @State private var batchToDelete: ImportBatch?

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
                Button {
                    Haptics.play(.selection)
                    exportBackup()
                } label: {
                    HStack {
                        Label {
                            Text("Export everything (JSON)").foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "square.and.arrow.up.on.square").foregroundStyle(Theme.accent)
                        }
                        if isExportingBackup { Spacer(); ProgressView() }
                    }
                }
                .disabled(isExportingBackup)
                Button {
                    Haptics.play(.selection)
                    showingRestorePicker = true
                } label: {
                    HStack {
                        Label {
                            Text("Restore from backup").foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
                        }
                        if isRestoring { Spacer(); ProgressView() }
                    }
                }
                .disabled(isRestoring)
                Toggle(isOn: Binding(
                    get: { AutoBackup.isEnabled },
                    set: { on in
                        Haptics.play(.selection)
                        AutoBackup.isEnabled = on
                        if on { AutoBackup.runIfDue(modelContainer: env.modelContainer) }
                    }
                )) {
                    Label {
                        Text("Weekly auto-backup").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.accent)
                    }
                }
                .tint(Theme.accent)
            } header: {
                Text("Backup")
            } footer: {
                Text("The complete journal — every record family, with ids and provenance — as one JSON file you own. Restoring inserts only the records you don't already have; nothing is overwritten or duplicated. Auto-backup writes the same file weekly to Files → On My iPhone → Prvital → Backups, keeping the last four.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            if hasDemoData {
                Section {
                    Button(role: .destructive) {
                        Haptics.play(.warning)
                        Task {
                            let seeder = DemoDataSeeder(modelContainer: env.modelContainer)
                            _ = await seeder.removeAll()
                            hasDemoData = false
                            refreshCounts()
                            env.entryStore.onChange()
                        }
                    } label: {
                        Label("Remove demo data", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Deletes exactly the sample week added during onboarding — nothing you logged yourself.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }

            if !importBatches.isEmpty {
                Section {
                    ForEach(importBatches) { batch in
                        importBatchRow(batch)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Haptics.play(.warning)
                                    batchToDelete = batch
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Imported files")
                } footer: {
                    Text("Everything a file added is grouped here. Tap ✕ to remove that import completely — use it if you loaded the wrong file. Entries you logged by hand, or that synced live, are never touched.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }

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
        .prvitalScreenBackground()
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
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [.json]
        ) { result in
            handleRestore(result)
        }
        // Written file in hand → straight to the share sheet.
        .sheet(item: Binding(
            get: { backupFileURL.map(BackupFileItem.init) },
            set: { if $0 == nil { backupFileURL = nil } }
        )) { item in
            BackupShareSheet(url: item.url)
        }
        .alert("Import", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage)
        }
        .confirmationDialog(
            "Remove this import?",
            isPresented: Binding(get: { batchToDelete != nil }, set: { if !$0 { batchToDelete = nil } }),
            titleVisibility: .visible,
            presenting: batchToDelete
        ) { batch in
            Button("Remove \(batch.totalCount) records", role: .destructive) {
                env.entryStore.deleteImportBatch(batch)
                refreshCounts()
                batchToDelete = nil
            }
            Button("Cancel", role: .cancel) { batchToDelete = nil }
        } message: { batch in
            Text("This removes everything this file added. It can't be undone, but you can import the file again.")
        }
    }

    // MARK: - Imported files

    @ViewBuilder
    private func importBatchRow(_ batch: ImportBatch) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(batch.filename ?? batch.formatName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(batch.importedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                // Language-neutral per-type counts (icons + numbers), so you can
                // see how much glucose / insulin / meals / activity the file added.
                HStack(spacing: 10) {
                    if batch.glucoseCount > 0 { countChip("drop.fill", batch.glucoseCount, Theme.zoneInRange) }
                    if batch.insulinCount > 0 { countChip("syringe.fill", batch.insulinCount, Theme.accent) }
                    if batch.carbCount > 0 { countChip("fork.knife", batch.carbCount, Theme.zoneHigh) }
                    if batch.activityCount > 0 { countChip("figure.walk", batch.activityCount, Theme.zoneWarning) }
                }
                .font(.caption2.weight(.semibold))
            }

            Spacer(minLength: 8)

            Button {
                Haptics.play(.warning)
                batchToDelete = batch
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this import")
        }
        .padding(.vertical, 2)
    }

    private func countChip(_ symbol: String, _ count: Int, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(count.formatted())
        }
        .foregroundStyle(tint)
    }

    private func exportBackup() {
        isExportingBackup = true
        Task {
            let store = JournalBackupStore(modelContainer: env.modelContainer)
            let url = try? await store.writeBackupFile()
            isExportingBackup = false
            backupFileURL = url
        }
    }

    private func handleRestore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        isRestoring = true
        Task {
            let store = JournalBackupStore(modelContainer: env.modelContainer)
            let inserted = (try? await store.restore(from: url)) ?? 0
            isRestoring = false
            importResultMessage = String(localized: "Restored \(inserted) records from the backup.")
            showingImportResult = true
            refreshCounts()
            env.entryStore.onChange()
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
                    result.rows, alreadySkipped: result.skipped,
                    filename: url.lastPathComponent, formatName: format.displayName)
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

// MARK: - Backup share plumbing

/// Wraps the written backup file so `.sheet(item:)` can present it.
private struct BackupFileItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Hands the finished backup file to the system share sheet.
private struct BackupShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.arrow.up.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Save it somewhere only you control — Files, iCloud Drive, or straight to another device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Text("Share backup")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
