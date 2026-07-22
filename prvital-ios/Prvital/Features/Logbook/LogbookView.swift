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
        "\(range.rawValue)|\(glucose.count)|\(insulin.count)|\(carbs.count)|\(observations.count)"
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
            .sheet(item: $sheetTarget) { target in editorSheet(for: target) }
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
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(range.title).font(.system(size: 15, weight: .semibold))
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
        Text(LocalizedStringKey(title))
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
                glucoseCell(row.cell(for: slot))
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
    /// edits it; tapping an empty cell opens a blank glucose sheet.
    private func glucoseCell(_ cell: LogbookCell) -> some View {
        Button {
            Haptics.play(.selection)
            if let id = cell.readingID, let reading = fetchReading(id) {
                sheetTarget = LogbookSheetTarget(kind: .glucose(reading))
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func insulinCell(_ row: LogbookRow, meal: Int) -> some View {
        let column = row.insulinColumns[meal]
        return Button {
            Haptics.play(.selection)
            if column.doseIDs.count == 1, let dose = fetchDose(column.doseIDs[0]) {
                sheetTarget = LogbookSheetTarget(kind: .insulin(dose))
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
        Text("Values are matched to each slot from your entries (fingerstick checks preferred; sensor readings fill in). Tap any cell to add or edit. Sharing opens the system sheet, where Print is available.")
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
    }
    let id = UUID()
    let kind: Kind
}

private struct LogbookShareItem: Identifiable {
    let url: URL
    var id: URL { url }
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
