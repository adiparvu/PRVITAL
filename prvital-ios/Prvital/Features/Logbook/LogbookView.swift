import SwiftUI
import SwiftData

/// The Registru — the classic paper diabetes logbook, auto-filled from the
/// journal's data. A pinned date column plus a horizontally scrollable table
/// with the register's columns: glucose before/after each meal and at bedtime,
/// insulin per meal, and comments. Tapping a cell opens the matching editor;
/// the toolbar share button renders the register as an A4-landscape PDF and
/// offers it through the system share sheet (which includes Print).
/// The register table's content, without its own `NavigationStack`/title, so the
/// Journal tab embeds it as its "Logbook" mode (Faza 1).
struct LogbookContent: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    // Declared so the view re-renders when the in-app language changes: the
    // headers and range labels resolve through `PrvitalString` (runtime strings,
    // which SwiftUI's `\.locale` does not re-resolve on its own).
    @Environment(\.locale) private var locale

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var observations: [ObservationEntry]

    /// The widest register window is one year, so the queries never need more
    /// than ~370 days. Windowing them here keeps a synced (or freshly imported)
    /// 100k+-row table off the main thread — the builder still slices to the
    /// selected `interval` below.
    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _observations = Query(filter: #Predicate<ObservationEntry> { $0.timestamp >= cutoff },
                              sort: \.timestamp, order: .reverse)
    }

    @State private var range: LogbookRange = .week
    @State private var sheetTarget: LogbookSheetTarget?
    @State private var shareItem: LogbookShareItem?
    @State private var errorMessage: String?
    @State private var showingError = false

    // The built register, cached in state and rebuilt only when the window or the
    // underlying data changes — never on every body pass. Building can touch up
    // to a year of readings, so doing it inline in `body` (re-run on scroll and
    // sheet animation) risked stalling the main thread; deferring it behind a
    // `.task` lets the sheet present first, then fills the table in.
    @State private var rows: [LogbookRow] = []
    @State private var isBuilding = false
    /// Bumped when an editor sheet closes, so in-place edits (value changes,
    /// slot pins, meal re-tags) rebuild the table even though the record
    /// counts — the rest of `rebuildKey` — did not move.
    @State private var dataVersion = 0

    // Fixed metrics keep the pinned date column and the scrolling grid aligned.
    private static let rowHeight: CGFloat = 44
    private static let headerHeight: CGFloat = 48
    private static let dateColumnWidth: CGFloat = 86
    private static let glucoseColumnWidth: CGFloat = 72
    private static let insulinColumnWidth: CGFloat = 64
    private static let commentsColumnWidth: CGFloat = 216

    private static let insulinTitles = ["Insulin breakfast", "Insulin lunch", "Insulin dinner"]

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var calendar: Calendar { .current }

    private var interval: DateInterval {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: now) ?? now
        return DateInterval(start: calendar.startOfDay(for: start), end: now)
    }

    /// Changes whenever the window or the underlying data does, so `.task(id:)`
    /// rebuilds exactly then — not on every scroll or animation frame.
    private var rebuildKey: String {
        "\(range.rawValue)|\(glucose.count)|\(insulin.count)|\(carbs.count)|\(observations.count)|\(locale.identifier)|\(dataVersion)"
    }

    /// Rebuilds the register. Yields first so the sheet finishes presenting, then
    /// runs the pure builder once. Cheap for a day/week; the year window is the
    /// only heavy case and it no longer blocks the sheet from opening.
    private func rebuild() async {
        isBuilding = true
        await Task.yield()
        rows = LogbookBuilder.rows(
            readings: glucose,
            insulin: insulin,
            carbs: carbs,
            observations: observations,
            interval: interval,
            calendar: calendar,
            anchors: LogbookAnchors(scheduleSlots: env.preferences.glucoseSchedule.slots)
        )
        isBuilding = false
    }

    var body: some View {
        Group {
                if isBuilding && rows.isEmpty {
                    ProgressView("Building the register…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            systemImage: "tablecells",
                            title: "Nothing in this period",
                            message: "Log glucose, insulin, meals and notes — the register fills itself in."
                        )
                        .padding(.top, 72)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            table(rows)
                            footnote
                        }
                        .padding()
                    }
                }
            }
            .task(id: rebuildKey) { await rebuild() }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { rangeMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.play(.light)
                        share(rows)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(rows.isEmpty)
                    .accessibilityLabel("Share logbook PDF")
                }
            }
            .sheet(item: $sheetTarget, onDismiss: { dataVersion += 1 }) { target in
                editorSheet(for: target)
            }
            .sheet(item: $shareItem) { item in
                LogbookSharePanel(url: item.url)
                    .presentationDetents([.height(250)])
            }
            .alert("Could not create the PDF", isPresented: $showingError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    // MARK: - Range picker

    /// Menu with a checkmark on the current window (Day … 1 year).
    private var rangeMenu: some View {
        Menu {
            Picker("Period", selection: $range) {
                ForEach(LogbookRange.allCases) { option in
                    Text(verbatim: PrvitalString(option.title)).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: PrvitalString(range.title)).font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
        }
        .accessibilityLabel("Choose period")
    }

    // MARK: - Table

    private func table(_ rows: [LogbookRow]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            dateColumn(rows)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.hairline).frame(width: 0.5)
                }
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(rows) { row in gridRow(row) }
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 0)
    }

    private func dateColumn(_ rows: [LogbookRow]) -> some View {
        VStack(spacing: 0) {
            headerCell("Date", width: Self.dateColumnWidth)
            ForEach(rows) { row in
                VStack(spacing: 2) {
                    Text(row.day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(row.day.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: Self.dateColumnWidth, height: Self.rowHeight)
                .overlay(alignment: .bottom) { rowSeparator }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(LogbookGlucoseSlot.allCases, id: \.self) { slot in
                headerCell(slot.title, width: Self.glucoseColumnWidth)
            }
            ForEach(Self.insulinTitles, id: \.self) { title in
                headerCell(title, width: Self.insulinColumnWidth)
            }
            headerCell("Comments", width: Self.commentsColumnWidth)
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(verbatim: PrvitalString(title))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(width: width, height: Self.headerHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
    }

    private func gridRow(_ row: LogbookRow) -> some View {
        HStack(spacing: 0) {
            ForEach(LogbookGlucoseSlot.allCases, id: \.self) { slot in
                glucoseCell(row.cell(for: slot), slot: slot)
            }
            ForEach(0..<3, id: \.self) { meal in
                insulinCell(row, meal: meal)
            }
            commentsCell(row)
        }
        .overlay(alignment: .bottom) { rowSeparator }
    }

    private var rowSeparator: some View {
        Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 0.5)
    }

    /// Zone-tinted glucose value, or an em-dash. Tapping an existing reading
    /// opens the slot sheet (provenance + move + edit); tapping an empty cell
    /// opens a blank glucose sheet. A pinned reading carries a small pin.
    private func glucoseCell(_ cell: LogbookCell, slot: LogbookGlucoseSlot) -> some View {
        Button {
            Haptics.play(.selection)
            if let id = cell.readingID, let reading = fetchReading(id) {
                sheetTarget = LogbookSheetTarget(kind: .slot(reading, slot))
            } else {
                sheetTarget = LogbookSheetTarget(kind: .glucose(nil))
            }
        } label: {
            Group {
                if let mgdL = cell.mgdL {
                    Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(thresholds.zone(forMgdL: mgdL).color)
                } else {
                    emptyMark
                }
            }
            .frame(width: Self.glucoseColumnWidth, height: Self.rowHeight)
            .overlay(alignment: .topTrailing) {
                if cell.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 5)
                        .padding(.trailing, 5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func insulinCell(_ row: LogbookRow, meal: Int) -> some View {
        let column = row.insulinColumns[meal]
        return Button {
            Haptics.play(.selection)
            let doses = column.doseIDs.compactMap(fetchDose)
            if doses.count == 1 {
                sheetTarget = LogbookSheetTarget(kind: .insulin(doses[0]))
            } else if doses.count > 1 {
                sheetTarget = LogbookSheetTarget(kind: .doses(doses))
            } else {
                sheetTarget = LogbookSheetTarget(kind: .insulin(nil))
            }
        } label: {
            Group {
                if let units = column.units {
                    Text(units.formatted())
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                } else {
                    emptyMark
                }
            }
            .frame(width: Self.insulinColumnWidth, height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func commentsCell(_ row: LogbookRow) -> some View {
        Button {
            Haptics.play(.selection)
            let dayObservations = observations.filter {
                calendar.isDate($0.timestamp, inSameDayAs: row.day)
            }
            sheetTarget = LogbookSheetTarget(
                kind: .observation(dayObservations.count == 1 ? dayObservations[0] : nil)
            )
        } label: {
            Group {
                if row.comment.isEmpty {
                    emptyMark
                } else {
                    Text(row.comment)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: Self.commentsColumnWidth, height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyMark: some View {
        Text(verbatim: "—")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Theme.textTertiary)
    }

    private var footnote: some View {
        Text("Values are matched to each slot from your entries (fingerstick checks preferred; sensor readings fill in). Tap a filled cell to pin it to a column or edit it; doses tagged with a meal always land in that meal's column. Sharing opens the system sheet, where Print is available.")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Editing

    /// Fetch by the model's `id: UUID` field (not the SwiftData persistent
    /// identifier), matching how records reference each other across the app.
    private func fetchReading(_ id: UUID) -> GlucoseReading? {
        var descriptor = FetchDescriptor<GlucoseReading>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchDose(_ id: UUID) -> InsulinDose? {
        var descriptor = FetchDescriptor<InsulinDose>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    @ViewBuilder
    private func editorSheet(for target: LogbookSheetTarget) -> some View {
        switch target.kind {
        case .glucose(let reading):
            GlucoseEntrySheet(existing: reading)
        case .insulin(let dose):
            InsulinEntrySheet(existing: dose)
        case .observation(let entry):
            ObservationEntrySheet(existing: entry)
        case .slot(let reading, let slot):
            LogbookSlotSheet(reading: reading, slot: slot, unit: unit, thresholds: thresholds) {
                sheetTarget = LogbookSheetTarget(kind: .glucose(reading))
            }
            .presentationDetents([.medium, .large])
        case .doses(let doses):
            LogbookDoseListSheet(doses: doses) { dose in
                sheetTarget = LogbookSheetTarget(kind: .insulin(dose))
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sharing

    private func share(_ rows: [LogbookRow]) {
        do {
            let name = env.profile.current().displayName.trimmingCharacters(in: .whitespaces)
            let url = try LogbookPDFComposer.writePDF(
                rows: rows,
                unit: unit,
                periodLabel: range.periodLabel,
                patientName: name.isEmpty ? nil : name
            )
            shareItem = LogbookShareItem(url: url)
            Haptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            Haptics.play(.warning)
        }
    }
}

// MARK: - Range

/// The register's window: today back through a year, as whole days.
private enum LogbookRange: String, CaseIterable, Identifiable {
    case day, week, month, threeMonths, sixMonths, nineMonths, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .threeMonths: return String(localized: "3 months")
        case .sixMonths: return String(localized: "6 months")
        case .nineMonths: return String(localized: "9 months")
        case .year: return String(localized: "1 year")
        }
    }

    /// Calendar days covered, counting today.
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 91
        case .sixMonths: return 182
        case .nineMonths: return 273
        case .year: return 365
        }
    }

    /// Human phrase for the PDF header.
    var periodLabel: String {
        switch self {
        case .day: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .threeMonths: return "Last 3 months"
        case .sixMonths: return "Last 6 months"
        case .nineMonths: return "Last 9 months"
        case .year: return "Last 12 months"
        }
    }
}

// MARK: - Sheet plumbing

/// Identifiable wrapper so a tapped cell can drive `.sheet(item:)`.
private struct LogbookSheetTarget: Identifiable {
    enum Kind {
        case glucose(GlucoseReading?)
        case insulin(InsulinDose?)
        case observation(ObservationEntry?)
        /// The slot sheet for a filled glucose cell: provenance + move + edit.
        case slot(GlucoseReading, LogbookGlucoseSlot)
        /// The dose list behind a multi-dose insulin cell.
        case doses([InsulinDose])
    }
    let id = UUID()
    let kind: Kind
}

private struct LogbookShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The sheet behind a filled glucose cell: the reading, whether it was pinned
/// here or placed automatically, one-tap moves to another column (which write
/// the explicit pin), and a door into the full editor.
private struct LogbookSlotSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let reading: GlucoseReading
    let slot: LogbookGlucoseSlot
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds
    /// Asks the parent to swap this sheet for the full glucose editor.
    var onEdit: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(GlucoseFormatting.string(mgdL: reading.valueMgdL, unit: unit))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(thresholds.zone(forMgdL: reading.valueMgdL).color)
                        Text(verbatim: unit.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(reading.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(verbatim: PrvitalString(reading.measurementType.label))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Label {
                        // if/else (not a ternary) so each literal stays a
                        // LocalizedStringKey — a ternary would collapse them
                        // into a plain String and skip the catalog.
                        Group {
                            if reading.logbookSlot != nil {
                                Text("Pinned to this column by you")
                            } else {
                                Text("Placed automatically, nearest to this column's time")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    } icon: {
                        Image(systemName: reading.logbookSlot != nil ? "pin.fill" : "wand.and.stars")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .prvioListRow()

                Section("Show in column") {
                    slotRow(title: String(localized: "Automatic"),
                            selected: reading.logbookSlot == nil) { pin(nil) }
                    ForEach(LogbookGlucoseSlot.allCases, id: \.self) { candidate in
                        slotRow(title: candidate.title,
                                selected: reading.logbookSlot == candidate) { pin(candidate) }
                    }
                }
                .prvioListRow()

                Section {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit reading", systemImage: "pencil")
                    }
                }
                .prvioListRow()
            }
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("Register slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func slotRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: PrvitalString(title))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// Writes the explicit pin (or clears it back to automatic) and closes.
    private func pin(_ newSlot: LogbookGlucoseSlot?) {
        reading.logbookSlot = newSlot
        env.entryStore.touch(reading)
        Haptics.play(.success)
        dismiss()
    }
}

/// The dose list behind a multi-dose insulin cell: every dose that counted
/// toward the column, each one tap away from the full editor (where its meal
/// tag can be changed).
private struct LogbookDoseListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let doses: [InsulinDose]
    /// Asks the parent to swap this sheet for the dose editor.
    var onSelect: (InsulinDose) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(doses, id: \.id) { dose in
                        Button {
                            onSelect(dose)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: "\(dose.units.formatted()) U")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(dose.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Text(verbatim: PrvitalString(dose.mealTag?.label ?? dose.doseContext.label))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text("Tap a dose to edit it — including which meal it belongs to.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .prvioListRow()
            }
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("Doses at this meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The post-generation panel, mirroring ExportView's ShareLink mechanism: the
/// PDF is already written to a temporary file; sharing (or printing, via the
/// system sheet) is the user's explicit choice.
private struct LogbookSharePanel: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Logbook PDF ready", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text(url.lastPathComponent)
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            ShareLink(item: url) {
                Label("Share or print", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Text("The share sheet includes Print — pick it to put the register on paper for your doctor.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { LogbookContent() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
