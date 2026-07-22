import SwiftUI
import SwiftData

// Dedicated pages behind the dashboard's three "Recent" tiles (Insulin, Meals,
// Activity). Each is a windowed list of that single entry type — newest first,
// tap a row to edit, swipe to delete — so the tile is a real doorway into the
// full log for that kind, not just a static summary.
//
// Every query is bounded to a recent window and the render is capped, so a
// full-history import can't materialise thousands of rows on the main thread.

// MARK: - Insulin

struct InsulinLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var doses: [InsulinDose]
    @State private var editing: InsulinDose?

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
            ForEach(Array(doses.prefix(Self.renderCap))) { dose in
                Button { Haptics.play(.selection); editing = dose } label: {
                    EntryLogRow(systemImage: "syringe.fill", tint: Theme.accent,
                                value: String(localized: "\(dose.units.formatted()) U"),
                                title: dose.insulinType.label, note: dose.note,
                                date: dose.timestamp)
                }
                .listRowBackground(Theme.surface)
                .swipeActions {
                    Button(role: .destructive) { env.entryStore.delete(dose) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Insulin")
        .sheet(item: $editing) { InsulinEntrySheet(existing: $0) }
    }
}

// MARK: - Meals

struct MealLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var meals: [CarbEntry]
    @State private var editing: CarbEntry?

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
            ForEach(Array(meals.prefix(Self.renderCap))) { meal in
                Button { Haptics.play(.selection); editing = meal } label: {
                    EntryLogRow(systemImage: "fork.knife", tint: Theme.zoneHigh,
                                value: String(localized: "\(meal.grams.formatted()) g"),
                                title: meal.mealType.label,
                                note: meal.foodDescription ?? meal.note,
                                date: meal.timestamp)
                }
                .listRowBackground(Theme.surface)
                .swipeActions {
                    Button(role: .destructive) { env.entryStore.delete(meal) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Meals")
        .sheet(item: $editing) { CarbEntrySheet(existing: $0) }
    }
}

// MARK: - Activity

struct ActivityLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var sessions: [ActivityEntry]
    @State private var editing: ActivityEntry?

    private static let renderCap = 500

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date())
            ?? Date().addingTimeInterval(-370 * 86_400)
        _sessions = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
    }

    var body: some View {
        EntryLogList(isEmpty: sessions.isEmpty, emptyImage: "figure.walk",
                     emptyTitle: "No activity", capped: sessions.count > Self.renderCap) {
            ForEach(Array(sessions.prefix(Self.renderCap))) { session in
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
        }
        .navigationTitle("Activity")
        .sheet(item: $editing) { ActivityEntrySheet(existing: $0) }
    }
}

// MARK: - Shared list + row

/// The shared chrome for a single-type entry log: an empty state, a themed
/// list, and an optional "showing the most recent" footer when the render was
/// capped. Content is the caller's `ForEach` of rows.
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
                    Section {
                        content
                    } footer: {
                        if capped {
                            Text("Showing your most recent entries.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
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

/// One entry row: a tinted glyph, the value + type on one line, and the
/// date/time (plus an optional note) beneath.
private struct EntryLogRow: View {
    let systemImage: String
    let tint: Color
    let value: String
    /// Already-localized entry-type label (e.g. "Rapid-acting", "Lunch").
    let title: String
    var note: String?
    let date: Date

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
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                if let note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
