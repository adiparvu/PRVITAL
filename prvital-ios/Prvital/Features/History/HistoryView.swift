import SwiftUI
import SwiftData

/// History: the same entries as the Journal, but framed as a searchable ledger.
///
/// A range filter (Today / Yesterday / This week / This month / Custom) and a
/// newest⇄oldest sort toggle drive a flat list. Rows swipe to delete through
/// `env.entryStore` and tap to edit, exactly like the Journal.
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var glucose: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]
    @Query(sort: \ObservationEntry.timestamp, order: .reverse) private var observations: [ObservationEntry]

    @State private var range: HistoryRange = .thisWeek
    @State private var sortNewestFirst = true
    @State private var showingCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var editTarget: HistoryEditTarget?

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    /// The most rows we ever hand to the `List`. A CGM logs ~288 readings/day, so
    /// "This month" (or a full-history import) can be tens of thousands of items;
    /// binding all of them into `List { ForEach }` makes SwiftUI hash and lay out
    /// every id on the main thread, which watchdog-kills the app. We render the
    /// most recent `renderCap` and tell the user to narrow the range for more.
    private static let renderCap = 500

    private var filteredItems: [JournalTimelineItem] {
        let interval = dateInterval
        return JournalTimelineItem.build(
            glucose: glucose, insulin: insulin, carbs: carbs,
            activity: activity, observations: observations
        )
        .filter { interval?.contains($0.date) ?? true }
        .sorted { sortNewestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    /// The capped slice actually rendered, plus whether more were withheld.
    private var visibleItems: ArraySlice<JournalTimelineItem> {
        filteredItems.prefix(Self.renderCap)
    }

    /// The half-open date interval selected by the current filter.
    private var dateInterval: DateInterval? {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .day, for: yesterday)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .custom:
            let lower = calendar.startOfDay(for: customStart)
            let upperDay = calendar.startOfDay(for: customEnd)
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            return DateInterval(start: min(lower, upper), end: max(lower, upper))
        }
    }

    private var summaryText: String {
        let count = filteredItems.count
        return count == 1
            ? String(localized: "\(count) entry · \(range.label)")
            : String(localized: "\(count) entries · \(range.label)")
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text(summaryText)
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
                            ForEach(visibleItems) { item in
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
                            }
                        } header: {
                            Text(summaryText)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .textCase(nil)
                        } footer: {
                            if filteredItems.count > Self.renderCap {
                                Text("Showing the most recent \(Self.renderCap.formatted()). Narrow the range to see the rest.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .animation(.snappy, value: sortNewestFirst)
            .animation(.default, value: range)
            .background(Theme.background)
            .navigationTitle("History")
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
            .sheet(item: $editTarget) { target in
                editorSheet(for: target.item)
            }
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

/// Identifiable wrapper so a tapped row can drive `.sheet(item:)`.
private struct HistoryEditTarget: Identifiable {
    let id = UUID()
    let item: JournalTimelineItem
}
