import SwiftUI
import SwiftData

// Dedicated pages behind the dashboard's three "Recent" tiles (Insulin, Meals,
// Activity). Each is a windowed list of that single entry type — newest first,
// grouped into dated day sections, tap a row to edit, swipe to delete — so the
// tile is a real doorway into the full log for that kind, not just a summary.
//
// Every query is bounded to a recent window and the render is capped, so a
// full-history import can't materialise thousands of rows on the main thread.

// MARK: - Insulin

struct InsulinLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var doses: [InsulinDose]
    @State private var editing: InsulinDose?
    // Glucose (value + trend) at each injection's time, matched from the CGM
    // history. Computed off the render path in a `.task` and cached by dose id.
    @State private var glucoseByDose: [UUID: GlucoseEventContext] = [:]

    private static let renderCap = 500

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _doses = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
    }

    var body: some View {
        EntryLogList(isEmpty: doses.isEmpty, emptyImage: "syringe.fill",
                     emptyTitle: "No doses", capped: doses.count > Self.renderCap) {
            ForEach(groupedByDay(Array(doses.prefix(Self.renderCap)), date: { $0.timestamp })) { group in
                Section {
                    ForEach(group.items) { dose in
                        Button { Haptics.play(.selection); editing = dose } label: {
                            EntryLogRow(systemImage: "syringe.fill", tint: Theme.accent,
                                        value: String(localized: "\(dose.units.formatted()) U"),
                                        title: dose.insulinType.label, note: dose.note,
                                        date: dose.timestamp,
                                        glucose: glucoseByDose[dose.id])
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button(role: .destructive) { env.entryStore.delete(dose) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { DayHeader(group.day) }
            }
        }
        .navigationTitle("Insulin")
        .sheet(item: $editing) { InsulinEntrySheet(existing: $0) }
        .task(id: doses.count) { await loadGlucoseContexts() }
    }

    /// Fetches the CGM readings spanning the visible doses once, then binary-search
    /// matches each dose to its nearest reading — so the whole list gets its
    /// glucose-at-injection chips without materialising the full history per row.
    private func loadGlucoseContexts() async {
        let visible = Array(doses.prefix(Self.renderCap))
        guard let lo = visible.map(\.timestamp).min(),
              let hi = visible.map(\.timestamp).max() else { glucoseByDose = [:]; return }
        // Cap how far back we fetch readings so a light logger's 500 doses can't
        // pull a year of CGM; doses older than this simply show no chip.
        let floor = Date().addingTimeInterval(-120 * 86_400)
        let lower = max(lo.addingTimeInterval(-20 * 60), floor)
        let upper = hi.addingTimeInterval(20 * 60)
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)])
        let readings = (try? modelContext.fetch(descriptor)) ?? []
        let unit = env.preferences.glucoseUnit
        let thresholds = env.preferences.thresholds
        var map: [UUID: GlucoseEventContext] = [:]
        for dose in visible {
            if let ctx = GlucoseEventContext.nearest(to: dose.timestamp, in: readings,
                                                     unit: unit, thresholds: thresholds) {
                map[dose.id] = ctx
            }
        }
        glucoseByDose = map
    }
}

// MARK: - Meals

struct MealLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [CarbEntry]
    @State private var editing: CarbEntry?
    // Glucose (value + trend) at each meal's time, matched from the CGM history —
    // so each meal shows where your glucose was when you ate. Computed off the
    // render path in a `.task` and cached by meal id.
    @State private var glucoseByMeal: [UUID: GlucoseEventContext] = [:]

    private static let renderCap = 500

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _meals = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
    }

    var body: some View {
        EntryLogList(isEmpty: meals.isEmpty, emptyImage: "fork.knife",
                     emptyTitle: "No meals", capped: meals.count > Self.renderCap) {
            ForEach(groupedByDay(Array(meals.prefix(Self.renderCap)), date: { $0.timestamp })) { group in
                Section {
                    ForEach(group.items) { meal in
                        Button { Haptics.play(.selection); editing = meal } label: {
                            EntryLogRow(systemImage: "fork.knife", tint: Theme.zoneHigh,
                                        value: String(localized: "\(meal.grams.formatted()) g"),
                                        title: meal.mealType.label,
                                        note: meal.foodDescription ?? meal.note,
                                        date: meal.timestamp,
                                        glucose: glucoseByMeal[meal.id])
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button(role: .destructive) { env.entryStore.delete(meal) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { DayHeader(group.day) }
            }
        }
        .navigationTitle("Meals")
        .sheet(item: $editing) { CarbEntrySheet(existing: $0) }
        .task(id: meals.count) { await loadGlucoseContexts() }
    }

    /// Fetches the CGM readings spanning the visible meals once, then binary-search
    /// matches each meal to its nearest reading — so every meal gets its
    /// glucose-at-the-time chip without materialising the full history per row.
    private func loadGlucoseContexts() async {
        let visible = Array(meals.prefix(Self.renderCap))
        guard let lo = visible.map(\.timestamp).min(),
              let hi = visible.map(\.timestamp).max() else { glucoseByMeal = [:]; return }
        // Cap how far back we fetch readings so a light logger's 500 meals can't
        // pull a year of CGM; meals older than this simply show no chip.
        let floor = Date().addingTimeInterval(-120 * 86_400)
        let lower = max(lo.addingTimeInterval(-20 * 60), floor)
        let upper = hi.addingTimeInterval(20 * 60)
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)])
        let readings = (try? modelContext.fetch(descriptor)) ?? []
        let unit = env.preferences.glucoseUnit
        let thresholds = env.preferences.thresholds
        var map: [UUID: GlucoseEventContext] = [:]
        for meal in visible {
            if let ctx = GlucoseEventContext.nearest(to: meal.timestamp, in: readings,
                                                     unit: unit, thresholds: thresholds) {
                map[meal.id] = ctx
            }
        }
        glucoseByMeal = map
    }
}

// MARK: - Activity

struct ActivityLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var sessions: [ActivityEntry]
    @State private var editing: ActivityEntry?
    // Apple Health's daily exercise minutes (appleExerciseTime — the Watch's green
    // ring), fetched off the render path. Merged with logged workouts so every
    // active day appears here, not only the handful of manually logged sessions.
    @State private var exerciseByDay: [Date: Int] = [:]

    private static let renderCap = 500
    private static let exerciseDays = 90

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _sessions = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
    }

    /// Merges logged workouts and Apple Health exercise-minute totals into one
    /// list of dated day groups (newest day first). Each day carries its exercise
    /// total (0 when none) plus every logged session that day, so a day with only
    /// Watch activity still shows up.
    private var days: [ActivityDay] {
        let cal = Calendar.current
        let sessionsByDay = Dictionary(grouping: Array(sessions.prefix(Self.renderCap))) {
            cal.startOfDay(for: $0.startTimestamp)
        }
        let allDays = Set(sessionsByDay.keys).union(exerciseByDay.keys)
        return allDays.sorted(by: >).map { day in
            ActivityDay(day: day,
                        exerciseMinutes: exerciseByDay[day] ?? 0,
                        sessions: sessionsByDay[day] ?? [])
        }
    }

    var body: some View {
        let days = days
        EntryLogList(isEmpty: days.isEmpty, emptyImage: "figure.walk",
                     emptyTitle: "No activity", capped: sessions.count > Self.renderCap) {
            ForEach(days) { group in
                Section {
                    // The day's Apple Health exercise total, headlining the section.
                    if group.exerciseMinutes > 0 {
                        ExerciseSummaryRow(minutes: group.exerciseMinutes)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(group.sessions) { session in
                        Button { Haptics.play(.selection); editing = session } label: {
                            EntryLogRow(systemImage: "figure.walk", tint: Theme.zoneInRange,
                                        value: String(localized: "\(session.durationMinutes) min"),
                                        title: session.activityType.label, note: session.note,
                                        date: session.startTimestamp)
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button(role: .destructive) { env.entryStore.delete(session) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { DayHeader(group.day) }
            }
        }
        .navigationTitle("Activity")
        .sheet(item: $editing) { ActivityEntrySheet(existing: $0) }
        .task { await loadExerciseMinutes() }
    }

    /// Reads Apple Health's daily exercise minutes for the recent window and keys
    /// them by start-of-day, so the merge in `days` is a cheap dictionary lookup.
    private func loadExerciseMinutes() async {
        let daily = await env.healthKit.dailyMetric(.exercise, days: Self.exerciseDays)
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for metric in daily {
            let minutes = Int(metric.value.rounded())
            if minutes > 0 { map[cal.startOfDay(for: metric.day)] = minutes }
        }
        exerciseByDay = map
    }
}

/// One calendar day in the activity log: its Apple Health exercise total (0 when
/// none) and the logged workouts recorded that day.
private struct ActivityDay: Identifiable {
    let day: Date
    let exerciseMinutes: Int
    let sessions: [ActivityEntry]
    var id: Date { day }
}

/// The day's Apple Health exercise minutes, shown as a non-editable headline row
/// above any logged workouts — the same figure the Move ring counts.
private struct ExerciseSummaryRow: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.zoneInRange, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "\(minutes) min"))
                        .font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Exercise").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Text("From Apple Health")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day grouping

/// One calendar day's worth of entries, newest day first.
private struct DayGroup<T: Identifiable>: Identifiable {
    let day: Date
    let items: [T]
    var id: Date { day }
}

/// Buckets already-sorted (newest-first) entries into day groups, newest day
/// first — the shape the logs render as dated sections. Grouping preserves each
/// bucket's original order, so entries stay newest-first within a day.
private func groupedByDay<T: Identifiable>(
    _ items: [T], date: (T) -> Date, calendar: Calendar = .current
) -> [DayGroup<T>] {
    let buckets = Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
    return buckets.keys.sorted(by: >).map { DayGroup(day: $0, items: buckets[$0] ?? []) }
}

/// A section header showing the day — "Today" / "Yesterday" for the two most
/// recent, otherwise the weekday and date. Formatted through the environment
/// locale so it follows the in-app language.
private struct DayHeader: View {
    let day: Date
    init(_ day: Date) { self.day = day }

    var body: some View {
        Group {
            if Calendar.current.isDateInToday(day) {
                Text("Today")
            } else if Calendar.current.isDateInYesterday(day) {
                Text("Yesterday")
            } else {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .textCase(nil)
    }
}

// MARK: - Shared list + row

/// The shared chrome for a single-type entry log: an empty state, a themed
/// list of dated day sections, and an optional "showing the most recent" footer
/// when the render was capped. Content is the caller's day `Section`s.
private struct EntryLogList<Content: View>: View {
    let isEmpty: Bool
    let emptyImage: String
    let emptyTitle: LocalizedStringKey
    let capped: Bool
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if isEmpty {
                EmptyStateView(systemImage: emptyImage, title: emptyTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    content
                    if capped {
                        Section {
                            Text("Showing your most recent entries.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .prvitalTabBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One entry row: a tinted glyph, the value + type on one line, and the time
/// (the day lives in the section header) plus an optional note beneath.
private struct EntryLogRow: View {
    let systemImage: String
    let tint: Color
    let value: String
    /// Already-localized entry-type label (e.g. "Rapid-acting", "Lunch").
    let title: String
    var note: String?
    let date: Date
    /// Glucose at the time of this entry (value + trend), when known.
    var glucose: GlucoseEventContext? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(value).font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                if let note, !note.isEmpty {
                    // Localized so an imported entry's "Imported" note follows the
                    // in-app language; free-text notes pass through unchanged.
                    Text(verbatim: PrvitalString(note)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                if let glucose {
                    glucose.chip.padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
