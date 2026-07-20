import SwiftUI
import SwiftData

/// The Journal: a reverse-chronological, day-grouped timeline of every entry.
///
/// Reads all five record types reactively via `@Query`, projects them into a
/// single `JournalTimelineItem` list, groups them by day with friendly
/// ("Today" / "Yesterday") headers, and lets any row be tapped to open the
/// matching editor pre-loaded with that record. The toolbar "+" opens the
/// quick-entry hub.
struct JournalView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var glucose: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]
    @Query(sort: \ObservationEntry.timestamp, order: .reverse) private var observations: [ObservationEntry]

    @State private var editTarget: JournalEditTarget?
    @State private var showingQuickEntry = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var items: [JournalTimelineItem] {
        JournalTimelineItem.build(
            glucose: glucose, insulin: insulin, carbs: carbs,
            activity: activity, observations: observations
        )
        .sorted { $0.date > $1.date }
    }

    private var sections: [JournalDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            JournalDaySection(day: day, items: grouped[day] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            systemImage: "book.closed",
                            title: "No entries yet",
                            message: "Log glucose, insulin, meals, activity and notes — they'll appear here on your timeline."
                        )
                        .padding(.top, 72)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                                Section {
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                            Button {
                                                Haptics.play(.selection)
                                                editTarget = JournalEditTarget(item: item)
                                            } label: {
                                                JournalEntryRow(item: item, unit: unit, thresholds: thresholds)
                                            }
                                            .buttonStyle(PressableCardStyle())
                                            if index < section.items.count - 1 {
                                                Divider().overlay(Theme.hairline)
                                            }
                                        }
                                    }
                                    .glassCard()
                                } header: {
                                    JournalSectionHeader(day: section.day)
                                }
                                .appearTransition(delay: Double(min(sectionIndex, 6)) * 0.05)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Journal")
            .toolbar {
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
        }
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

/// One day's worth of timeline items.
private struct JournalDaySection: Identifiable {
    let day: Date
    let items: [JournalTimelineItem]
    var id: Date { day }
}

/// Identifiable wrapper so a tapped row can drive `.sheet(item:)`.
private struct JournalEditTarget: Identifiable {
    let id = UUID()
    let item: JournalTimelineItem
}

/// A day header: "Today" / "Yesterday" / a formatted weekday-and-date.
private struct JournalSectionHeader: View {
    let day: Date

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
