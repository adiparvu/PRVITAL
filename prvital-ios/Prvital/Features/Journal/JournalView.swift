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
    @State private var mode: JournalMode = .days
    // Apple Health's daily exercise minutes (appleExerciseTime), merged into each
    // day card's "activity" so the Watch's Move-ring activity shows even on days
    // with no manually logged workout. Fetched off the render path.
    @State private var healthExerciseByDay: [Date: Int] = [:]

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
            thresholds: thresholds,
            healthExerciseByDay: healthExerciseByDay
        )
    }

    /// Reads the last two weeks of Apple Health exercise minutes and keys them by
    /// start-of-day for the day-card merge — the same figure the Move ring counts.
    private func loadHealthExercise() async {
        let daily = await env.healthKit.dailyMetric(.exercise, days: 15)
        let calendar = Calendar.current
        var map: [Date: Int] = [:]
        for metric in daily {
            let minutes = Int(metric.value.rounded())
            if minutes > 0 { map[calendar.startOfDay(for: metric.day)] = minutes }
        }
        healthExerciseByDay = map
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(JournalMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: mode) { _, _ in Haptics.play(.selection) }

                switch mode {
                case .days: daysContent
                case .list: HistoryContent()
                case .calendar: CalendarContent()
                case .register: LogbookContent()
                }
            }
            .prvitalTabBackground()
            .navigationTitle("Journal")
            .toolbar {
                // The density filter only applies to the day-cards mode; the "+"
                // is always available. Each mode contributes its own toolbar
                // actions (History's sort/range, Calendar's Today, Registru's
                // share) which merge in contextually.
                if mode == .days {
                    ToolbarItem(placement: .topBarLeading) {
                        filtersMenu
                    }
                }
                ToolbarItem(placement: .primaryAction) {
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
            .sheet(item: $editTarget) { target in
                editorSheet(for: target.item)
            }
            .task { await loadHealthExercise() }
        }
    }

    /// The day-cards feed — the default Journal mode (Tide Guide-style cards).
    private var daysContent: some View {
        let density = self.density
        let buckets = self.buckets
        return Group {
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
    }

    /// The "presets"-style card-density picker (three options with density icons,
    /// checkmark on the current choice, persisted through `Preferences`). Shown
    /// only in the day-cards mode.
    private var filtersMenu: some View {
        Menu {
            Picker("Card density", selection: densityBinding) {
                ForEach(JournalCardDensity.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Card density")
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

/// The Journal's view modes — the four "a day's data" screens, now united under
/// one tab instead of scattered across sheets and the Insights tab.
private enum JournalMode: String, CaseIterable, Identifiable {
    case days, list, calendar, register

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .days: return "Days"
        case .list: return "List"
        case .calendar: return "Calendar"
        case .register: return "Logbook"
        }
    }
}

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
