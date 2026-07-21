import SwiftUI

// MARK: - Card density

/// How much detail each journal day card shows, in the spirit of a Tide
/// Guide-style "presets" picker. Persisted through
/// `Preferences.journalCardDensityRaw` so the choice survives relaunches.
enum JournalCardDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }

    var symbol: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .standard: return "rectangle"
        case .detailed: return "rectangle.expand.vertical"
        }
    }

    /// Whether the carbs / insulin / activity / notes chip row is shown.
    var showsTherapyRow: Bool { self != .compact }
    /// Whether the day's full entry list is always visible inside the card.
    var showsEntryList: Bool { self == .detailed }
}

// MARK: - Per-day statistics

/// A pure, per-day roll-up shown on a journal day card: the glucose envelope
/// (lowest / highest with their times, average, time in range) plus therapy and
/// lifestyle totals. Deterministic given the inputs, so it is unit-testable
/// without any UI.
struct JournalDayStats: Equatable {
    var readingCount = 0
    var averageMgdL: Double = 0
    var lowestMgdL: Double = 0
    var lowestAt: Date?
    var highestMgdL: Double = 0
    var highestAt: Date?
    /// Fraction of readings inside the target range, 0...1.
    var timeInRange: Double = 0
    /// Zone of the day's average — the card's dominant tint.
    var zone: GlucoseZone = .inRange

    var totalCarbGrams: Double = 0
    var mealCount = 0
    var totalInsulinUnits: Double = 0
    var doseCount = 0
    var activityMinutes = 0
    var activityCount = 0
    var noteCount = 0

    var hasGlucose: Bool { readingCount > 0 }
    var entryCount: Int { readingCount + mealCount + doseCount + activityCount + noteCount }
    var hasTherapyData: Bool { mealCount > 0 || doseCount > 0 || activityCount > 0 || noteCount > 0 }

    /// Summarises one local day's records. Only *active* glucose readings count,
    /// mirroring `StatisticsEngine` and `CalendarAggregator`.
    static func build(
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        observations: [ObservationEntry],
        thresholds: GlucoseThresholds
    ) -> JournalDayStats {
        var stats = JournalDayStats()

        let active = readings.filter(\.isActive)
        if !active.isEmpty {
            let n = Double(active.count)
            stats.readingCount = active.count
            stats.averageMgdL = active.reduce(0) { $0 + $1.valueMgdL } / n
            if let lowest = active.min(by: { $0.valueMgdL < $1.valueMgdL }) {
                stats.lowestMgdL = lowest.valueMgdL
                stats.lowestAt = lowest.timestamp
            }
            if let highest = active.max(by: { $0.valueMgdL < $1.valueMgdL }) {
                stats.highestMgdL = highest.valueMgdL
                stats.highestAt = highest.timestamp
            }
            let inRange = active.filter { thresholds.inRange($0.valueMgdL) }.count
            stats.timeInRange = Double(inRange) / n
            stats.zone = thresholds.zone(forMgdL: stats.averageMgdL)
        }

        stats.totalInsulinUnits = insulin.reduce(0) { $0 + $1.units }
        stats.doseCount = insulin.count
        stats.totalCarbGrams = carbs.reduce(0) { $0 + $1.grams }
        stats.mealCount = carbs.count
        stats.activityMinutes = activity.reduce(0) { $0 + $1.durationMinutes }
        stats.activityCount = activity.count
        stats.noteCount = observations.count
        return stats
    }
}

// MARK: - Day bucketing

/// One local day's worth of journal records, ready to render as a day card:
/// the raw readings for the curve, the mixed entry list for the detailed view,
/// and the pre-computed statistics for the chip rows.
struct JournalDayBucket: Identifiable {
    /// Start of the local day.
    let day: Date
    /// The day's *active* glucose readings (any order; the chart sorts).
    let readings: [GlucoseReading]
    /// Every record of the day projected into timeline items, newest first.
    let items: [JournalTimelineItem]
    let stats: JournalDayStats

    var id: Date { day }

    /// Buckets the five record collections per local calendar day (mirroring
    /// `CalendarAggregator`), newest day first, capped at `maxDays` buckets so
    /// the feed stays a sensible window.
    static func build(
        glucose: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        observations: [ObservationEntry],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current,
        maxDays: Int = 14
    ) -> [JournalDayBucket] {
        func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

        let readingsByDay = Dictionary(grouping: glucose.filter(\.isActive)) { startOfDay($0.timestamp) }
        let insulinByDay = Dictionary(grouping: insulin) { startOfDay($0.timestamp) }
        let carbsByDay = Dictionary(grouping: carbs) { startOfDay($0.timestamp) }
        let activityByDay = Dictionary(grouping: activity) { startOfDay($0.startTimestamp) }
        let observationsByDay = Dictionary(grouping: observations) { startOfDay($0.timestamp) }

        let days = Set(readingsByDay.keys)
            .union(insulinByDay.keys)
            .union(carbsByDay.keys)
            .union(activityByDay.keys)
            .union(observationsByDay.keys)
            .sorted(by: >)
            .prefix(max(0, maxDays))

        return days.map { day in
            let dayReadings = readingsByDay[day] ?? []
            let dayInsulin = insulinByDay[day] ?? []
            let dayCarbs = carbsByDay[day] ?? []
            let dayActivity = activityByDay[day] ?? []
            let dayObservations = observationsByDay[day] ?? []
            return JournalDayBucket(
                day: day,
                readings: dayReadings,
                items: JournalTimelineItem.build(
                    glucose: dayReadings,
                    insulin: dayInsulin,
                    carbs: dayCarbs,
                    activity: dayActivity,
                    observations: dayObservations
                ).sorted { $0.date > $1.date },
                stats: JournalDayStats.build(
                    readings: dayReadings,
                    insulin: dayInsulin,
                    carbs: dayCarbs,
                    activity: dayActivity,
                    observations: dayObservations,
                    thresholds: thresholds
                )
            )
        }
    }
}

// MARK: - Day card

/// A Tide Guide-style day card: a big day header with a zone-tinted TIR ring
/// glyph, the day's compact glucose curve, then rows of small icon chips —
/// lowest / highest / average / time-in-range, and (standard and up) carbs /
/// insulin / activity / notes. The day's entries open on their own page (a
/// navigation push) rather than expanding inline — long days would otherwise
/// stretch the card across the whole screen; Detailed density additionally
/// previews the first few entries on the card.
struct JournalDayCard: View {
    let bucket: JournalDayBucket
    let density: JournalCardDensity
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds
    /// Called when an entry row is tapped, so the owner can present its editor.
    let onSelect: (JournalTimelineItem) -> Void

    /// How many entries the Detailed density previews on the card itself.
    private static let previewEntryCount = 3

    private var stats: JournalDayStats { bucket.stats }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The header, curve, ring and chips are one tap target: pressing any
            // of them opens the day's own page (per device feedback — "when you
            // press them, something should happen").
            NavigationLink {
                JournalDayDetailView(bucket: bucket, unit: unit, thresholds: thresholds, onSelect: onSelect)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !bucket.readings.isEmpty {
                        GlucoseTrendChart(readings: bucket.readings, thresholds: thresholds, unit: unit, compact: true)
                    }
                    if stats.hasGlucose {
                        glucoseChipRow
                    } else {
                        Text("No glucose readings this day")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if density.showsTherapyRow && stats.hasTherapyData {
                        therapyChipRow
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this day on its own page")

            if density.showsEntryList && !bucket.items.isEmpty {
                Divider().overlay(Theme.hairline)
                entryList(Array(bucket.items.prefix(Self.previewEntryCount)))
            }
            if !bucket.items.isEmpty {
                entriesLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26, padding: 18)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            glyph
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(headerAccessibilityText)
    }

    /// "Today" / "Yesterday" / the wide weekday name.
    private var titleText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(bucket.day) { return "Today" }
        if calendar.isDateInYesterday(bucket.day) { return "Yesterday" }
        return bucket.day.formatted(.dateTime.weekday(.wide))
    }

    /// "Jul 21" under the big title.
    private var dateText: String {
        bucket.day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The decorative context glyph, top right: a zone-tinted ring swept to the
    /// day's time-in-range with the percentage inside — or, on glucose-free
    /// days, a quiet entry-count badge.
    @ViewBuilder
    private var glyph: some View {
        if stats.hasGlucose {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: stats.timeInRange)
                    .stroke(stats.zone.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(tirPercent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(stats.zone.color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        } else if stats.entryCount > 0 {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 4)
                Text("\(stats.entryCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        }
    }

    private var tirPercent: Int { Int((stats.timeInRange * 100).rounded()) }

    private var headerAccessibilityText: String {
        var parts: [String] = ["\(titleText), \(bucket.day.formatted(.dateTime.month(.wide).day()))"]
        if stats.hasGlucose {
            parts.append("average \(GlucoseFormatting.labeled(mgdL: stats.averageMgdL, unit: unit))")
            parts.append("\(tirPercent) percent in range")
            if let lowestAt = stats.lowestAt {
                parts.append("lowest \(GlucoseFormatting.string(mgdL: stats.lowestMgdL, unit: unit)) at \(Self.timeText(lowestAt))")
            }
            if let highestAt = stats.highestAt {
                parts.append("highest \(GlucoseFormatting.string(mgdL: stats.highestMgdL, unit: unit)) at \(Self.timeText(highestAt))")
            }
        } else {
            parts.append("no glucose readings")
        }
        parts.append(stats.entryCount == 1 ? "1 entry" : "\(stats.entryCount) entries")
        return parts.joined(separator: ", ")
    }

    // MARK: Chip rows

    /// Row A — always shown when the day has glucose: lowest with its time,
    /// highest with its time, average, and time in range.
    private var glucoseChipRow: some View {
        Self.glucoseChips(stats: stats, unit: unit, thresholds: thresholds)
    }

    /// Row B — standard and detailed: carbs, insulin, activity, notes totals.
    private var therapyChipRow: some View {
        Self.therapyChips(stats: stats)
    }

    /// Shared with `JournalDayDetailView`, so the day page shows the exact same
    /// chips as the card.
    static func glucoseChips(stats: JournalDayStats, unit: GlucoseUnit, thresholds: GlucoseThresholds) -> some View {
        chipGrid {
            JournalStatChip(
                systemImage: "arrow.down",
                tint: thresholds.zone(forMgdL: stats.lowestMgdL).color,
                value: GlucoseFormatting.string(mgdL: stats.lowestMgdL, unit: unit),
                caption: stats.lowestAt.map(timeText)
            )
            JournalStatChip(
                systemImage: "arrow.up",
                tint: thresholds.zone(forMgdL: stats.highestMgdL).color,
                value: GlucoseFormatting.string(mgdL: stats.highestMgdL, unit: unit),
                caption: stats.highestAt.map(timeText)
            )
            JournalStatChip(
                systemImage: "chart.bar",
                tint: stats.zone.color,
                value: GlucoseFormatting.string(mgdL: stats.averageMgdL, unit: unit),
                caption: unit.rawValue
            )
            JournalStatChip(
                systemImage: "target",
                tint: Theme.zoneInRange,
                value: "\(Int((stats.timeInRange * 100).rounded()))%",
                caption: "in range"
            )
        }
    }

    static func therapyChips(stats: JournalDayStats) -> some View {
        chipGrid {
            JournalStatChip(
                systemImage: "fork.knife",
                tint: Theme.zoneHigh,
                value: "\(stats.totalCarbGrams.formatted()) g",
                caption: stats.mealCount == 1 ? "1 meal" : "\(stats.mealCount) meals"
            )
            JournalStatChip(
                systemImage: "syringe.fill",
                tint: Theme.accent,
                value: "\(stats.totalInsulinUnits.formatted()) U",
                caption: stats.doseCount == 1 ? "1 dose" : "\(stats.doseCount) doses"
            )
            JournalStatChip(
                systemImage: "figure.walk",
                tint: Theme.zoneInRange,
                value: "\(stats.activityMinutes) min",
                caption: stats.activityCount == 1 ? "1 session" : "\(stats.activityCount) sessions"
            )
            JournalStatChip(
                systemImage: "note.text",
                tint: Theme.textSecondary,
                value: "\(stats.noteCount)",
                caption: stats.noteCount == 1 ? "note" : "notes"
            )
        }
    }

    private static func chipGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            alignment: .leading,
            spacing: 10
        ) {
            content()
        }
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Entry list

    /// A few tappable entry rows — the same rows (and editors) the old flat
    /// timeline used, so no capability is lost.
    private func entryList(_ items: [JournalTimelineItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    JournalEntryRow(item: item, unit: unit, thresholds: thresholds)
                }
                .buttonStyle(PressableCardStyle())
                if index < items.count - 1 {
                    Divider().overlay(Theme.hairline)
                        .padding(.leading, 48)
                }
            }
        }
    }

    /// Footer link: the day's full entry list lives on its own page, so a
    /// 100-reading day never stretches the card down the whole screen.
    private var entriesLink: some View {
        NavigationLink {
            JournalDayDetailView(bucket: bucket, unit: unit, thresholds: thresholds, onSelect: onSelect)
        } label: {
            HStack(spacing: 5) {
                Text(showEntriesText)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .contentShape(.rect)
        }
        .buttonStyle(PressableChipStyle())
        .accessibilityLabel(showEntriesText)
        .accessibilityHint("Opens this day's entries on their own page")
    }

    private var showEntriesText: String {
        bucket.items.count == 1 ? "Show 1 entry" : "Show \(bucket.items.count) entries"
    }
}

// MARK: - Day detail page

/// One day on its own page: the full-size annotated glucose curve, every stat
/// chip, and the complete tappable entry list. Pushed from a day card's
/// entries link; editing goes through the same `onSelect` closure (and the
/// journal's editor sheets), so behavior matches the card exactly.
struct JournalDayDetailView: View {
    let bucket: JournalDayBucket
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds
    let onSelect: (JournalTimelineItem) -> Void

    private var stats: JournalDayStats { bucket.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !bucket.readings.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        GlucoseTrendChart(readings: bucket.readings, thresholds: thresholds, unit: unit, compact: false)
                    }
                    .glassCard(cornerRadius: 26, padding: 18)
                    .appearTransition(delay: 0)
                }

                VStack(alignment: .leading, spacing: 14) {
                    if stats.hasGlucose {
                        JournalDayCard.glucoseChips(stats: stats, unit: unit, thresholds: thresholds)
                    }
                    if stats.hasTherapyData {
                        JournalDayCard.therapyChips(stats: stats)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 26, padding: 18)
                .appearTransition(delay: 0.06)

                if !bucket.items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(bucket.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onSelect(item)
                            } label: {
                                JournalEntryRow(item: item, unit: unit, thresholds: thresholds)
                            }
                            .buttonStyle(PressableCardStyle())
                            if index < bucket.items.count - 1 {
                                Divider().overlay(Theme.hairline)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .glassCard(cornerRadius: 26, padding: 12)
                    .appearTransition(delay: 0.12)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(bucket.day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(bucket.day) { return String(localized: "Yesterday") }
        return bucket.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Stat chip

/// A small Tide Guide-style stat chip: a rounded-square tinted icon beside a
/// value with a tiny caption. Four of these make one card row.
struct JournalStatChip: View {
    let systemImage: String
    let tint: Color
    let value: String
    var caption: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Day card") {
    let now = Date()
    let readings = (0..<12).map { i in
        GlucoseReading(
            valueMgdL: [92, 105, 130, 168, 201, 176, 142, 118, 96, 64, 88, 121][i],
            timestamp: now.addingTimeInterval(Double(-i) * 5400)
        )
    }
    let insulin = [
        InsulinDose(units: 4, timestamp: now.addingTimeInterval(-3600)),
        InsulinDose(units: 12, timestamp: now.addingTimeInterval(-30000), insulinType: .longActing),
    ]
    let carbs = [
        CarbEntry(grams: 45, timestamp: now.addingTimeInterval(-4000), mealType: .breakfast, foodDescription: "Oats and berries"),
        CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-20000), mealType: .lunch),
    ]
    let activity = [ActivityEntry(startTimestamp: now.addingTimeInterval(-10000), durationSeconds: 1800)]
    let notes = [ObservationEntry(tags: [], text: "Slept badly", timestamp: now.addingTimeInterval(-500))]

    let bucket = JournalDayBucket.build(
        glucose: readings, insulin: insulin, carbs: carbs,
        activity: activity, observations: notes,
        thresholds: .standard
    ).first!

    return ScrollView {
        VStack(spacing: 20) {
            ForEach(JournalCardDensity.allCases) { density in
                JournalDayCard(
                    bucket: bucket,
                    density: density,
                    unit: .mgdL,
                    thresholds: .standard,
                    onSelect: { _ in }
                )
            }
        }
        .padding()
    }
    .background(Theme.background)
}
