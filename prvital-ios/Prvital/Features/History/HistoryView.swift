import SwiftUI
import SwiftData

/// History: the Journal's "List" mode, reframed as *the user's* ledger.
///
/// A CGM writes ~288 readings a day; as a flat list that is noise, not a
/// ledger — the sensor's story already lives in the chart, Days and Insights.
/// So by default this list shows only what the person logged themselves:
/// insulin, meals, fingerstick/manual/lab glucose, activity and notes. The
/// sensor stream stays available behind a toggle in the filter menu, and a
/// chip row narrows the list to one record family.
///
/// Performance contract: the SwiftData queries are bounded to the *selected
/// range* (not a year), sensor readings are excluded in the predicate itself
/// when hidden (so 100k rows are never materialised), the merged timeline is
/// built once per data change behind `.task(id:)`, and rendering is paged
/// ("Show more") instead of hard-capped.
struct HistoryContent: View {
    @Environment(AppEnvironment.self) private var env

    @State private var range: HistoryRange = .thisWeek
    @State private var kindFilter: HistoryKindFilter = .all
    @State private var showSensor = false
    @State private var sortNewestFirst = true
    @State private var showingCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()
    /// Free-text search across notes, foods, tags and values in the window.
    @State private var searchText = ""

    /// The half-open day-aligned interval selected by the current filter.
    private var dateInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
                ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return calendar.dateInterval(of: .day, for: yesterday)
                ?? DateInterval(start: calendar.startOfDay(for: yesterday), duration: 86_400)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
                ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
                ?? DateInterval(start: calendar.startOfDay(for: now), duration: 30 * 86_400)
        case .custom:
            let lower = calendar.startOfDay(for: customStart)
            let upperDay = calendar.startOfDay(for: customEnd)
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            return DateInterval(start: min(lower, upper), end: max(lower, upper))
        }
    }

    var body: some View {
        let interval = dateInterval
        VStack(spacing: 0) {
            chipRow
            HistoryListView(
                start: interval.start, end: interval.end, showSensor: showSensor,
                kindFilter: kindFilter, sortNewestFirst: sortNewestFirst,
                rangeLabel: range.label, searchText: searchText
            )
            // New identity per window / sensor choice → the bounded queries are
            // rebuilt for exactly that slice, and pagination starts over. The
            // search text is deliberately NOT part of the identity — typing
            // filters the already-built timeline in place.
            .id("\(interval.start.timeIntervalSince1970)|\(interval.end.timeIntervalSince1970)|\(showSensor)")
        }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text("Search notes, foods, tags…"))
            .animation(.snappy, value: kindFilter)
            .animation(.default, value: range)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy) { sortNewestFirst.toggle() }
                        Haptics.play(.selection)
                    } label: {
                        Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
                    }
                    .accessibilityLabel(sortNewestFirst ? "Sorted newest first" : "Sorted oldest first")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Range", selection: $range) {
                            ForEach(HistoryRange.allCases) { option in
                                Label(option.label, systemImage: option.symbol).tag(option)
                            }
                        }
                        if range == .custom {
                            Button {
                                showingCustomRange = true
                            } label: {
                                Label("Edit dates", systemImage: "calendar")
                            }
                        }
                        Divider()
                        Toggle(isOn: $showSensor) {
                            Label("Show sensor readings", systemImage: "sensor.tag.radiowaves.forward")
                        }
                    } label: {
                        Label(range.label, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onChange(of: range) { _, newValue in
                if newValue == .custom { showingCustomRange = true }
            }
            .sheet(isPresented: $showingCustomRange) {
                customRangeSheet
            }
    }

    /// One-tap record-family filter: All / Insulin / Meals / Glucose / Activity
    /// / Notes. Purely in-memory — switching chips never refetches.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryKindFilter.allCases) { filter in
                    let selected = kindFilter == filter
                    Button {
                        kindFilter = filter
                        Haptics.play(.selection)
                    } label: {
                        Label(filter.label, systemImage: filter.symbol)
                            .font(.footnote.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected ? Theme.accent : Theme.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingCustomRange = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Bounded list

/// The list itself, created fresh per (window, sensor) choice so its SwiftData
/// queries cover exactly the selected slice — a month of CGM is ~8.6k rows and
/// a week of *logged* entries is a few dozen, never a year of anything.
private struct HistoryListView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]

    let kindFilter: HistoryKindFilter
    let sortNewestFirst: Bool
    let rangeLabel: String
    let searchText: String
    private let showSensor: Bool

    /// The merged timeline, newest first — built once per data change in
    /// `.task(id:)`, never inline in `body` (a computed property here used to
    /// re-run the whole merge three or four times per render).
    @State private var items: [JournalTimelineItem] = []
    /// How many rows are rendered; "Show more" grows it page by page.
    @State private var visibleCount = HistoryListView.pageSize
    /// Bumped when the editor sheet closes, so in-place edits rebuild the list
    /// even though no record count moved.
    @State private var dataVersion = 0
    @State private var editTarget: HistoryEditTarget?

    private static let pageSize = 200

    init(start: Date, end: Date, showSensor: Bool,
         kindFilter: HistoryKindFilter, sortNewestFirst: Bool, rangeLabel: String,
         searchText: String = "") {
        self.showSensor = showSensor
        self.kindFilter = kindFilter
        self.sortNewestFirst = sortNewestFirst
        self.rangeLabel = rangeLabel
        self.searchText = searchText

        // Sensor readings are excluded in the predicate itself when hidden, so
        // SwiftData never materialises the 5-minute stream just to drop it.
        let cgmRaw = GlucoseMeasurementType.cgm.rawValue
        if showSensor {
            _glucose = Query(filter: #Predicate<GlucoseReading> {
                $0.timestamp >= start && $0.timestamp < end
            }, sort: \.timestamp, order: .reverse)
        } else {
            _glucose = Query(filter: #Predicate<GlucoseReading> {
                $0.timestamp >= start && $0.timestamp < end && $0.measurementTypeRaw != cgmRaw
            }, sort: \.timestamp, order: .reverse)
        }
        _insulin = Query(filter: #Predicate<InsulinDose> {
            $0.timestamp >= start && $0.timestamp < end
        }, sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> {
            $0.timestamp >= start && $0.timestamp < end
        }, sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> {
            $0.startTimestamp >= start && $0.startTimestamp < end
        }, sort: \.startTimestamp, order: .reverse)
        _observations = Query(filter: #Predicate<ObservationEntry> {
            $0.timestamp >= start && $0.timestamp < end
        }, sort: \.timestamp, order: .reverse)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var buildKey: String {
        "\(glucose.count)|\(insulin.count)|\(carbs.count)|\(activity.count)|\(observations.count)|\(dataVersion)"
    }

    /// The chip-filtered timeline in display order. Cheap: it maps over the
    /// cached array, no re-merge and no re-sort beyond an optional reverse.
    private var filteredItems: [JournalTimelineItem] {
        var matching = kindFilter == .all
            ? items
            : items.filter { kindFilter.matches($0.kind) }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            matching = matching.filter { $0.matchesSearch(query) }
        }
        return sortNewestFirst ? matching : matching.reversed()
    }

    var body: some View {
        let filtered = filteredItems
        let visible = Array(filtered.prefix(visibleCount))
        let summary = summaryText(count: filtered.count)

        Group {
            if filtered.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        EmptyStateView(
                            systemImage: "clock.arrow.circlepath",
                            title: "Nothing in this range",
                            message: "Choose a different period, or add a new entry."
                        )
                    }
                    .padding()
                }
            } else {
                List {
                    Section {
                        ForEach(visible) { item in
                            JournalEntryRow(item: item, unit: unit, thresholds: thresholds)
                                .listRowBackground(Theme.surface)
                                .listRowSeparatorTint(Theme.hairline)
                                .contentShape(.rect)
                                .onTapGesture {
                                    Haptics.play(.selection)
                                    editTarget = HistoryEditTarget(item: item)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                // "The same meal as yesterday" in one gesture:
                                // re-logs the entry as of NOW. Sensor readings
                                // are excluded — duplicating a CGM point would
                                // fabricate data the sensor never produced.
                                .swipeActions(edge: .leading) {
                                    if item.glucose?.measurementType != .cgm,
                                       item.glucose?.measurementType != .calibration {
                                        Button {
                                            duplicate(item)
                                        } label: {
                                            Label("Repeat now", systemImage: "plus.square.on.square")
                                        }
                                        .tint(Theme.accent)
                                    }
                                }
                        }
                        if filtered.count > visibleCount {
                            Button {
                                visibleCount += Self.pageSize
                                Haptics.play(.selection)
                            } label: {
                                Text("Show more")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(nil)
                    } footer: {
                        if !showSensor {
                            Text("Sensor readings are hidden — turn them on from the filter menu.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .task(id: buildKey) {
            // Yield first so tab/mode switches present before the merge runs.
            await Task.yield()
            items = JournalTimelineItem.build(
                glucose: glucose, insulin: insulin, carbs: carbs,
                activity: activity, observations: observations
            )
            .sorted { $0.date > $1.date }
        }
        .sheet(item: $editTarget, onDismiss: { dataVersion += 1 }) { target in
            editorSheet(for: target.item)
        }
    }

    private func summaryText(count: Int) -> String {
        count == 1
            ? String(localized: "\(count) entry · \(rangeLabel)")
            : String(localized: "\(count) entries · \(rangeLabel)")
    }

    /// Re-logs the entry with the current timestamp — the values travel, the
    /// moment doesn't. Manual provenance regardless of the original's source.
    private func duplicate(_ item: JournalTimelineItem) {
        switch item.kind {
        case .glucose:
            if let reading = item.glucose {
                _ = env.entryStore.addGlucose(
                    mgdL: reading.valueMgdL,
                    measurementType: reading.measurementType == .laboratory
                        ? .manual : reading.measurementType)
            }
        case .insulin:
            if let dose = item.insulin {
                env.entryStore.addInsulin(
                    units: dose.units, type: dose.insulinType, name: dose.insulinName,
                    deliveryMethod: dose.deliveryMethod, context: dose.doseContext,
                    mealTag: dose.mealTag, note: dose.note)
            }
        case .carbs:
            if let entry = item.carbs {
                env.entryStore.addCarbs(
                    grams: entry.grams, mealType: entry.mealType,
                    foodDescription: entry.foodDescription, note: entry.note)
            }
        case .activity:
            if let entry = item.activity {
                env.entryStore.addActivity(
                    type: entry.activityType, durationSeconds: entry.durationSeconds,
                    intensity: entry.intensity, caloriesBurned: entry.caloriesBurned,
                    distanceMeters: entry.distanceMeters, note: entry.note)
            }
        case .observation:
            if let entry = item.observation {
                env.entryStore.addObservation(tags: entry.tags, text: entry.text)
            }
        }
        Haptics.play(.success)
        dataVersion += 1
    }

    private func delete(_ item: JournalTimelineItem) {
        switch item.kind {
        case .glucose:
            if let reading = item.glucose { env.entryStore.delete(reading) }
        case .insulin:
            if let dose = item.insulin { env.entryStore.delete(dose) }
        case .carbs:
            if let entry = item.carbs { env.entryStore.delete(entry) }
        case .activity:
            if let entry = item.activity { env.entryStore.delete(entry) }
        case .observation:
            if let entry = item.observation { env.entryStore.delete(entry) }
        }
        Haptics.play(.warning)
    }

    @ViewBuilder
    private func editorSheet(for item: JournalTimelineItem) -> some View {
        switch item.kind {
        case .glucose:
            if let reading = item.glucose { GlucoseEntrySheet(existing: reading) }
        case .insulin:
            if let dose = item.insulin { InsulinEntrySheet(existing: dose) }
        case .carbs:
            if let entry = item.carbs { CarbEntrySheet(existing: entry) }
        case .activity:
            if let entry = item.activity { ActivityEntrySheet(existing: entry) }
        case .observation:
            if let entry = item.observation { ObservationEntrySheet(existing: entry) }
        }
    }
}

// MARK: - Private helpers

/// The selectable time windows for the History filter.
private enum HistoryRange: String, CaseIterable, Identifiable {
    case today, yesterday, thisWeek, thisMonth, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .thisWeek: return String(localized: "This week")
        case .thisMonth: return String(localized: "This month")
        case .custom: return String(localized: "Custom")
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .yesterday: return "clock.arrow.circlepath"
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar.badge.clock"
        case .custom: return "slider.horizontal.3"
        }
    }
}

/// The chip row's record-family filter.
private enum HistoryKindFilter: String, CaseIterable, Identifiable {
    case all, insulin, meals, glucose, activity, notes

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .insulin: "Insulin"
        case .meals: "Meals"
        case .glucose: "Glucose"
        case .activity: "Activity"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal"
        case .insulin: "syringe"
        case .meals: "fork.knife"
        case .glucose: "drop"
        case .activity: "figure.walk"
        case .notes: "note.text"
        }
    }

    func matches(_ kind: JournalTimelineItem.Kind) -> Bool {
        switch self {
        case .all: true
        case .insulin: kind == .insulin
        case .meals: kind == .carbs
        case .glucose: kind == .glucose
        case .activity: kind == .activity
        case .notes: kind == .observation
        }
    }
}

/// Identifiable wrapper so a tapped row can drive `.sheet(item:)`.
private struct HistoryEditTarget: Identifiable {
    let id = UUID()
    let item: JournalTimelineItem
}

// MARK: - Free-text search

extension JournalTimelineItem {
    /// Case- and diacritic-insensitive match over everything a person might
    /// remember about an entry: food names, notes, tags, kinds and values.
    func matchesSearch(_ query: String) -> Bool {
        haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var haystack: String {
        var parts: [String] = []
        if let glucose {
            parts.append(String(Int(glucose.valueMgdL.rounded())))
            parts.append(glucose.measurementType.label)
        }
        if let insulin {
            parts.append(insulin.insulinName ?? "")
            parts.append(insulin.note ?? "")
            parts.append(insulin.insulinType.label)
        }
        if let carbs {
            parts.append(carbs.foodDescription ?? "")
            parts.append(carbs.note ?? "")
            parts.append(carbs.mealType.label)
        }
        if let activity {
            parts.append(activity.note ?? "")
            parts.append(activity.activityType.label)
        }
        if let observation {
            parts.append(observation.text ?? "")
            parts.append(contentsOf: observation.tags.map(\.label))
        }
        return parts.joined(separator: " ")
    }
}
