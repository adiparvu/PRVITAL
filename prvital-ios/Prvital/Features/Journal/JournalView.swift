import SwiftUI
import SwiftData

/// The Journal: a vertical feed of Tide Guide-style day cards, newest first.
///
/// Reads all five record types reactively via `@Query`, buckets them per local
/// day (capped at the most recent 14 days with data), and renders each day as a
/// glass card: big day header with a TIR ring glyph, the day's compact glucose
/// curve, icon-chip stat rows, and — depending on the chosen density — the
/// day's entry list. Every entry row still opens its matching editor, the
/// toolbar "+" opens the quick-entry hub, and the calendar button reaches any
/// older day. A toolbar presets menu switches Compact / Standard / Detailed,
/// persisted via `Preferences.journalCardDensityRaw`.
struct JournalView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]

    /// The Journal shows at most the 14 most-recent days *with data*, so the
    /// queries only need a recent window — never the whole (potentially 100k-row,
    /// post-import) history. Without this bound, every CGM sync re-materialised
    /// the entire table on the main thread just to bucket the last two weeks.
    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date())
            ?? Date().addingTimeInterval(-120 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
        _observations = Query(filter: #Predicate<ObservationEntry> { $0.timestamp >= cutoff },
                              sort: \.timestamp, order: .reverse)
    }

    @State private var editTarget: JournalEditTarget?
    @State private var showingQuickEntry = false
    @State private var showingCalendar = false
    @State private var showingLogbook = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var density: JournalCardDensity {
        JournalCardDensity(rawValue: env.preferences.journalCardDensityRaw) ?? .standard
    }

    private var densityBinding: Binding<JournalCardDensity> {
        Binding(
            get: { JournalCardDensity(rawValue: env.preferences.journalCardDensityRaw) ?? .standard },
            set: { newValue in
                Haptics.play(.selection)
                env.preferences.journalCardDensityRaw = newValue.rawValue
            }
        )
    }

    private var buckets: [JournalDayBucket] {
        JournalDayBucket.build(
            glucose: glucose, insulin: insulin, carbs: carbs,
            activity: activity, observations: observations,
            thresholds: thresholds
        )
    }

    var body: some View {
        let density = self.density
        let buckets = self.buckets

        return NavigationStack {
            Group {
                if buckets.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            systemImage: "book.closed",
                            title: "No entries yet",
                            message: "Log glucose, insulin, meals, activity and notes — they'll appear here as day cards."
                        )
                        .padding(.top, 72)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                                JournalDayCard(
                                    bucket: bucket,
                                    density: density,
                                    unit: unit,
                                    thresholds: thresholds
                                ) { item in
                                    Haptics.play(.selection)
                                    editTarget = JournalEditTarget(item: item)
                                }
                                .appearTransition(delay: Double(min(index, 6)) * 0.05)
                            }
                        }
                        .padding()
                        .animation(.snappy, value: density)
                    }
                }
            }
            .prvitalTabBackground()
            .navigationTitle("Journal")
            .toolbar {
                // One filters menu on the left (density + calendar united, per
                // device feedback), the logbook and "+" on the right.
                ToolbarItem(placement: .topBarLeading) {
                    filtersMenu
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Haptics.play(.selection)
                        showingLogbook = true
                    } label: {
                        Image(systemName: "tablecells")
                    }
                    .accessibilityLabel("Open logbook")
                    Button {
                        Haptics.play(.light)
                        showingQuickEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add entry")
                }
            }
            .sheet(isPresented: $showingQuickEntry) {
                QuickEntrySheet()
            }
            .sheet(isPresented: $showingCalendar) {
                CalendarView()
            }
            .sheet(isPresented: $showingLogbook) {
                LogbookView()
            }
            .sheet(item: $editTarget) { target in
                editorSheet(for: target.item)
            }
        }
    }

    /// One united filters menu: the "presets"-style density picker (three
    /// options with density icons, checkmark on the current choice, persisted
    /// through `Preferences`) plus the calendar jump.
    private var filtersMenu: some View {
        Menu {
            Picker("Card density", selection: densityBinding) {
                ForEach(JournalCardDensity.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            Divider()
            Button {
                Haptics.play(.selection)
                showingCalendar = true
            } label: {
                Label("Open calendar", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filters")
    }

    @ViewBuilder
    private func editorSheet(for item: JournalTimelineItem) -> some View {
        switch item.kind {
        case .glucose:
            if let reading = item.glucose { GlucoseEntrySheet(existing: reading) }
        case .insulin:
            if let dose = item.insulin { InsulinEntrySheet(existing: dose) }
        case .carbs:
            // A meal opens its postprandial response page (with an Edit action
            // inside) rather than the bare editor — the richer default.
            if let entry = item.carbs { MealResponseView(meal: entry) }
        case .activity:
            if let entry = item.activity { ActivityEntrySheet(existing: entry) }
        case .observation:
            if let entry = item.observation { ObservationEntrySheet(existing: entry) }
        }
    }
}

// MARK: - Private helpers

/// Identifiable wrapper so a tapped row can drive `.sheet(item:)`.
private struct JournalEditTarget: Identifiable {
    let id = UUID()
    let item: JournalTimelineItem
}

#Preview {
    let env = AppEnvironment.preview()
    return JournalView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
