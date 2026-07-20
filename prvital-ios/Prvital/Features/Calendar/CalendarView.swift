import SwiftUI
import SwiftData

/// The Calendar — a month-at-a-glance view of the journal. Each day is tinted by
/// its mean-glucose zone and shows a tiny average (or a dot for days that only
/// carry non-glucose entries). Reads are reactive `@Query`s that are bucketed by
/// `CalendarAggregator`; tapping a day with data opens a detail sheet with that
/// day's glucose statistics and a compact, self-rendered list of its entries.
struct CalendarView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var readings: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]
    @Query(sort: \ObservationEntry.timestamp, order: .reverse) private var observations: [ObservationEntry]

    /// Any date inside the month currently on screen.
    @State private var visibleMonth: Date = Date()
    /// The tapped day, presented as a detail sheet.
    @State private var selection: CalendarDaySelection?

    private var calendar: Calendar { .current }

    var body: some View {
        let thresholds = env.preferences.thresholds
        let unit = env.preferences.glucoseUnit
        let summaries = CalendarAggregator.summaries(
            readings: readings,
            insulin: insulin,
            carbs: carbs,
            activity: activity,
            thresholds: thresholds,
            calendar: calendar
        )
        let cells = calendarGridCells(for: visibleMonth, calendar: calendar)

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthCard(cells: cells, summaries: summaries, unit: unit)
                    legend
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.play(.selection)
                        withAnimation(.snappy) { visibleMonth = Date() }
                    } label: {
                        Text("Today").font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Jump to current month")
                }
            }
            .sheet(item: $selection) { selected in
                CalendarDayDetailSheet(
                    date: selected.date,
                    readings: records(readings, on: selected.date) { $0.timestamp },
                    insulin: records(insulin, on: selected.date) { $0.timestamp },
                    carbs: records(carbs, on: selected.date) { $0.timestamp },
                    activity: records(activity, on: selected.date) { $0.startTimestamp },
                    observations: records(observations, on: selected.date) { $0.timestamp },
                    unit: unit,
                    thresholds: thresholds,
                    calendar: calendar
                )
            }
        }
    }

    // MARK: - Month card

    @ViewBuilder
    private func monthCard(
        cells: [CalendarGridCell],
        summaries: [Date: DaySummary],
        unit: GlucoseUnit
    ) -> some View {
        VStack(spacing: 16) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        let day = calendar.startOfDay(for: date)
                        CalendarDayCell(
                            date: date,
                            summary: summaries[day],
                            isToday: calendar.isDateInToday(date),
                            unit: unit,
                            calendar: calendar
                        ) {
                            Haptics.play(.light)
                            selection = CalendarDaySelection(date: date)
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
            .id(visibleMonth)
            .transition(.blurReplace)
        }
        .glassCard(cornerRadius: 26, padding: 18)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(calendarMonthTitle(visibleMonth))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(Array(orderedWeekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private var legend: some View {
        SectionCard("Legend", systemImage: "circle.grid.2x2") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CalendarLegendItem.all) { item in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(item.color.opacity(0.5))
                            .frame(width: 18, height: 18)
                        Text(item.label)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.label)
                }
                HStack(spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        .frame(width: 18, height: 18)
                    Text("Entries only (no glucose reading)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    // MARK: - Actions & filtering

    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        Haptics.play(.selection)
        withAnimation(.snappy) { visibleMonth = next }
    }

    /// Filters a homogeneous record collection down to a single calendar day.
    private func records<R>(_ all: [R], on day: Date, timestamp: (R) -> Date) -> [R] {
        all.filter { calendar.isDate(timestamp($0), inSameDayAs: day) }
    }
}

// MARK: - Day cell

private struct CalendarDayCell: View {
    let date: Date
    let summary: DaySummary?
    let isToday: Bool
    let unit: GlucoseUnit
    let calendar: Calendar
    let action: () -> Void

    private var dayNumber: Int { calendar.component(.day, from: date) }
    private var hasData: Bool { summary?.hasData ?? false }
    private var hasGlucose: Bool { (summary?.readingCount ?? 0) > 0 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(size: 15, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(hasData ? Theme.textPrimary : Theme.textTertiary)

                if let summary, hasGlucose {
                    Text(GlucoseFormatting.string(mgdL: summary.averageMgdL, unit: unit))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(summary.zone.color)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else if hasData {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                } else {
                    Text(" ").font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cellBackground)
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!hasData)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(hasData ? "Opens day detail" : "")
        .accessibilityAddTraits(hasData ? .isButton : [])
    }

    private var cellBackground: Color {
        if let summary, summary.hasData {
            return hasGlucose ? summary.zone.color.opacity(0.18) : Theme.accentSoft.opacity(0.7)
        }
        return Theme.surface.opacity(0.35)
    }

    private var accessibilityText: String {
        let dateText = date.formatted(.dateTime.weekday(.wide).month().day())
        let prefix = isToday ? "Today, \(dateText)" : dateText
        guard let summary, summary.hasData else { return "\(prefix), no data" }
        if summary.readingCount > 0 {
            let avg = GlucoseFormatting.labeled(mgdL: summary.averageMgdL, unit: unit)
            let tir = Int((summary.timeInRange * 100).rounded())
            return "\(prefix), average \(avg), \(tir) percent in range, \(summary.entryCount) entries, \(summary.zone.label)"
        }
        return "\(prefix), \(summary.entryCount) entries"
    }
}

// MARK: - Day detail sheet

private struct CalendarDayDetailSheet: View {
    let date: Date
    let readings: [GlucoseReading]
    let insulin: [InsulinDose]
    let carbs: [CarbEntry]
    let activity: [ActivityEntry]
    let observations: [ObservationEntry]
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds
    let calendar: Calendar

    @Environment(\.dismiss) private var dismiss

    private var stats: PeriodStatistics {
        StatisticsEngine.glucose(readings, thresholds: thresholds)
    }

    private var entries: [CalendarEntryItem] {
        CalendarEntryItem.build(
            insulin: insulin,
            carbs: carbs,
            activity: activity,
            observations: observations
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    glucoseSection
                    entriesSection
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Glucose statistics

    @ViewBuilder
    private var glucoseSection: some View {
        SectionCard("Glucose", systemImage: "drop.fill") {
            if stats.hasGlucose {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(
                        title: "Average",
                        value: GlucoseFormatting.string(mgdL: stats.average, unit: unit),
                        caption: unit.rawValue,
                        tint: thresholds.zone(forMgdL: stats.average).color,
                        systemImage: "chart.bar"
                    )
                    StatTile(
                        title: "Time in range",
                        value: "\(Int((stats.timeInRange * 100).rounded()))%",
                        caption: "\(stats.readingCount) readings",
                        tint: Theme.zoneInRange,
                        systemImage: "target"
                    )
                    StatTile(
                        title: "Lowest",
                        value: GlucoseFormatting.string(mgdL: stats.minimum, unit: unit),
                        caption: unit.rawValue,
                        tint: thresholds.zone(forMgdL: stats.minimum).color,
                        systemImage: "arrow.down"
                    )
                    StatTile(
                        title: "Highest",
                        value: GlucoseFormatting.string(mgdL: stats.maximum, unit: unit),
                        caption: unit.rawValue,
                        tint: thresholds.zone(forMgdL: stats.maximum).color,
                        systemImage: "arrow.up"
                    )
                }
            } else {
                EmptyStateView(
                    systemImage: "drop",
                    title: "No glucose readings",
                    message: "This day has entries but no glucose values."
                )
            }
        }
    }

    // MARK: Entry list

    @ViewBuilder
    private var entriesSection: some View {
        SectionCard("Entries", systemImage: "list.bullet") {
            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "No entries",
                    message: "Insulin, meals, activity and notes for this day appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { item in
                        CalendarEntryRowView(item: item)
                        if item.id != entries.last?.id {
                            Divider().background(Theme.hairline).padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compact entry row

private struct CalendarEntryRowView: View {
    let item: CalendarEntryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 32, height: 32)
                .background(item.tint.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityText)
    }
}

// MARK: - Fileprivate models

/// Identifiable wrapper so a tapped day drives `.sheet(item:)`.
private struct CalendarDaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

/// One slot in the month grid — a real day, or a leading blank (`date == nil`).
private struct CalendarGridCell: Identifiable {
    let id: Int
    let date: Date?
}

/// A normalised, self-rendered event row for the day-detail list.
private struct CalendarEntryItem: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let date: Date

    var accessibilityText: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return "\(title)\(subtitle.map { ", \($0)" } ?? ""), \(time)"
    }

    /// Merges every non-glucose record type into one time-ordered list (newest first).
    static func build(
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        observations: [ObservationEntry]
    ) -> [CalendarEntryItem] {
        var items: [CalendarEntryItem] = []

        for dose in insulin {
            items.append(CalendarEntryItem(
                id: "insulin-\(dose.id)",
                icon: "syringe.fill",
                tint: Theme.accent,
                title: "\(dose.units.formatted()) U · \(dose.insulinType.label)",
                subtitle: [dose.doseContext.label, dose.insulinName].compactMap { $0 }.joined(separator: " · "),
                date: dose.timestamp
            ))
        }

        for meal in carbs {
            items.append(CalendarEntryItem(
                id: "carbs-\(meal.id)",
                icon: meal.mealType.symbol,
                tint: Theme.zoneHigh,
                title: "\(meal.grams.formatted()) g · \(meal.mealType.label)",
                subtitle: meal.foodDescription,
                date: meal.timestamp
            ))
        }

        for session in activity {
            items.append(CalendarEntryItem(
                id: "activity-\(session.id)",
                icon: session.activityType.symbol,
                tint: Theme.zoneInRange,
                title: session.activityType.label,
                subtitle: "\(session.durationMinutes) min · \(session.intensity.label)",
                date: session.startTimestamp
            ))
        }

        for note in observations {
            let title = note.tags.isEmpty ? "Note" : note.tags.map(\.label).joined(separator: ", ")
            items.append(CalendarEntryItem(
                id: "observation-\(note.id)",
                icon: note.tags.first?.symbol ?? "note.text",
                tint: Theme.zoneWarning,
                title: title,
                subtitle: note.text,
                date: note.timestamp
            ))
        }

        return items.sorted { $0.date > $1.date }
    }
}

/// A single legend swatch (zone colours the calendar uses to tint days).
private struct CalendarLegendItem: Identifiable {
    let id = UUID()
    let color: Color
    let label: String

    static let all: [CalendarLegendItem] = [
        CalendarLegendItem(color: Theme.zoneInRange, label: "Average in range"),
        CalendarLegendItem(color: Theme.zoneHigh, label: "Average high"),
        CalendarLegendItem(color: Theme.zoneWarning, label: "Average low or very high"),
        CalendarLegendItem(color: Theme.zoneCritical, label: "Average very low"),
    ]
}

// MARK: - Fileprivate date helpers

/// Builds the month grid: leading blanks for the first weekday, then each day.
private func calendarGridCells(for month: Date, calendar: Calendar) -> [CalendarGridCell] {
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
    let firstOfMonth = interval.start
    let weekday = calendar.component(.weekday, from: firstOfMonth)
    let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

    var cells: [CalendarGridCell] = []
    var index = 0
    for _ in 0..<leadingBlanks {
        cells.append(CalendarGridCell(id: index, date: nil))
        index += 1
    }
    for day in range {
        if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
            cells.append(CalendarGridCell(id: index, date: date))
            index += 1
        }
    }
    return cells
}

/// Weekday initials reordered to respect the locale's first weekday.
private func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
    let symbols = calendar.veryShortWeekdaySymbols
    guard !symbols.isEmpty else { return symbols }
    let first = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
    return Array(symbols[first...] + symbols[..<first])
}

/// "July 2026" style month title.
private func calendarMonthTitle(_ date: Date) -> String {
    date.formatted(.dateTime.month(.wide).year())
}

#Preview {
    let env = AppEnvironment.preview()
    return CalendarView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
