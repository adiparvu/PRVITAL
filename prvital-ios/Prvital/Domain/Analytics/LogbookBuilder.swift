import Foundation

// MARK: - Registru (classic diabetes logbook) — pure builder
//
// Builds the rows of the paper register Romanian diabetologists ask patients to
// keep: one line per day with glucose before/after each meal and at bedtime,
// the insulin taken at each meal, and a comments column. Pure Foundation, no
// SwiftData queries — the view hands in the already-fetched records.
//
// Slot rules (documented here because they ARE the feature):
//   • Meal anchors come from the user's OWN word first: the day's earliest
//     carb entry DECLARED as breakfast / lunch / dinner anchors that meal at
//     the moment it was actually eaten. Snacks never move a meal. Only when a
//     day has no declared entry for a meal does the clock take over: breakfast
//     07:30, lunch 13:00, dinner 19:00, bedtime 22:30 — overridden by the
//     glucose schedule's enabled slots, bucketed by time of day
//     (04:00–10:59 → breakfast, 11:00–15:59 → lunch, 16:00–20:59 → dinner,
//     21:00 onwards or before 04:00 → bedtime; earliest slot in a band wins).
//   • A "before X" glucose slot looks BACKWARD from the meal: the nearest
//     reading in the 90 minutes leading up to the first bite (with a 10-minute
//     grace after it, for logging order) — a value from well after eating can
//     never be "before". "2h after X" targets anchor + 2 h and bedtime targets
//     its anchor, both within ±75 min. Fingerstick / manual / lab readings are
//     preferred over CGM whenever any is inside the window — the paper
//     register is meant for discrete checks — with CGM used only as a
//     fallback. A reading fills at most one slot (closest first, in
//     chronological slot order).
//   • Insulin per meal is the sum of *bolus* doses (anything except basal: a
//     dose is excluded when its context is `.basal` or its insulin type is
//     basal/long-acting) within ±90 min of the meal's anchor; each dose counts
//     toward its nearest anchor only. `nil` means no dose.
//   • The comment joins the day's observation texts, then appends short
//     markers for lows below the threshold (default 70 mg/dL), e.g.
//     "Low 47 at 02:51". Consecutive low readings within 30 min group into one
//     episode reported at its lowest value; at most 3 episodes are listed.
//   • Only days with at least one record (active reading, bolus dose, carb
//     entry or observation) produce a row; rows are newest first.

/// One glucose cell of the register: the representative reading (if any) and
/// the slot's target instant that day (used for context on empty cells).
struct LogbookCell: Equatable, Sendable {
    var mgdL: Double?
    var readingID: UUID?
    var slotDate: Date
}

/// The seven glucose columns of the register, in paper order.
enum LogbookGlucoseSlot: CaseIterable, Sendable {
    case beforeBreakfast, afterBreakfast, beforeLunch, afterLunch
    case beforeDinner, afterDinner, bedtime

    /// Compact column header (the views may break it into two lines).
    var title: String {
        switch self {
        case .beforeBreakfast: return String(localized: "Before breakfast")
        case .afterBreakfast: return String(localized: "2h after breakfast")
        case .beforeLunch: return String(localized: "Before lunch")
        case .afterLunch: return String(localized: "2h after lunch")
        case .beforeDinner: return String(localized: "Before dinner")
        case .afterDinner: return String(localized: "2h after dinner")
        case .bedtime: return String(localized: "Bedtime")
        }
    }
}

/// One day of the register.
struct LogbookRow: Identifiable, Sendable {
    /// Start of the calendar day.
    var day: Date

    var beforeBreakfast: LogbookCell
    var afterBreakfast: LogbookCell
    var beforeLunch: LogbookCell
    var afterLunch: LogbookCell
    var beforeDinner: LogbookCell
    var afterDinner: LogbookCell
    var bedtime: LogbookCell

    /// Summed bolus units around each meal anchor; nil when no dose.
    var breakfastUnits: Double?
    var breakfastDoseIDs: [UUID]
    var lunchUnits: Double?
    var lunchDoseIDs: [UUID]
    var dinnerUnits: Double?
    var dinnerDoseIDs: [UUID]

    /// Observation texts plus auto low markers, "; "-joined. Empty when none.
    var comment: String

    var id: Date { day }

    func cell(for slot: LogbookGlucoseSlot) -> LogbookCell {
        switch slot {
        case .beforeBreakfast: return beforeBreakfast
        case .afterBreakfast: return afterBreakfast
        case .beforeLunch: return beforeLunch
        case .afterLunch: return afterLunch
        case .beforeDinner: return beforeDinner
        case .afterDinner: return afterDinner
        case .bedtime: return bedtime
        }
    }

    /// The three insulin columns in paper order (breakfast, lunch, dinner).
    var insulinColumns: [(units: Double?, doseIDs: [UUID])] {
        [(breakfastUnits, breakfastDoseIDs), (lunchUnits, lunchDoseIDs), (dinnerUnits, dinnerDoseIDs)]
    }
}

/// Meal anchor times as minutes from midnight, defaulting to the classic
/// register timetable (07:30 / 13:00 / 19:00 / bedtime 22:30).
struct LogbookAnchors: Equatable, Sendable {
    var breakfastMinutes: Int = 7 * 60 + 30
    var lunchMinutes: Int = 13 * 60
    var dinnerMinutes: Int = 19 * 60
    var bedtimeMinutes: Int = 22 * 60 + 30

    static let standard = LogbookAnchors()

    init(breakfastMinutes: Int = 7 * 60 + 30, lunchMinutes: Int = 13 * 60,
         dinnerMinutes: Int = 19 * 60, bedtimeMinutes: Int = 22 * 60 + 30) {
        self.breakfastMinutes = breakfastMinutes
        self.lunchMinutes = lunchMinutes
        self.dinnerMinutes = dinnerMinutes
        self.bedtimeMinutes = bedtimeMinutes
    }

    /// Derives anchors from the user's chosen glucose-logging slots. Labels are
    /// free text, so slots are bucketed by time of day instead: 04:00–10:59 →
    /// breakfast, 11:00–15:59 → lunch, 16:00–20:59 → dinner, and 21:00 onwards
    /// (or before 04:00, a night owl's bedtime) → bedtime. The earliest enabled
    /// slot in each band wins; bands without a slot keep the defaults above.
    init(scheduleSlots: [GlucoseLogSlot]) {
        self.init()
        let enabled = scheduleSlots.filter(\.enabled)

        func earliest(_ range: Range<Int>) -> Int? {
            enabled.map(\.minutesFromMidnight).filter { range.contains($0) }.min()
        }
        if let m = earliest(4 * 60 ..< 11 * 60) { breakfastMinutes = m }
        if let m = earliest(11 * 60 ..< 16 * 60) { lunchMinutes = m }
        if let m = earliest(16 * 60 ..< 21 * 60) { dinnerMinutes = m }
        // Bedtime wraps midnight: order candidates on a 21:00-anchored clock so
        // 23:00 sorts before 01:30.
        let bedtimeCandidates = enabled.map(\.minutesFromMidnight)
            .filter { $0 >= 21 * 60 || $0 < 4 * 60 }
        if let m = bedtimeCandidates.min(by: { wrapped($0) < wrapped($1) }) { bedtimeMinutes = m }
    }

    private func wrapped(_ minutes: Int) -> Int {
        minutes < 4 * 60 ? minutes + 24 * 60 : minutes
    }
}

/// Builds the register rows. Pure and deterministic — safe to unit-test.
enum LogbookBuilder {
    /// Half-width of the symmetric glucose windows (±75 min around the target)
    /// used by the "2h after" and bedtime slots.
    static let glucoseWindow: TimeInterval = 75 * 60
    /// How far BACK a "before meal" slot looks from the meal anchor (90 min)…
    static let beforeMealLookback: TimeInterval = 90 * 60
    /// …and the little grace after the anchor for measure-then-log ordering.
    static let beforeMealGrace: TimeInterval = 10 * 60
    /// Half-width of the insulin meal window (±90 min around the anchor).
    static let insulinWindow: TimeInterval = 90 * 60
    /// "After X" targets the meal anchor plus two hours.
    static let afterMealOffset: TimeInterval = 2 * 60 * 60
    /// Low readings closer than this group into one comment marker.
    static let lowEpisodeGap: TimeInterval = 30 * 60
    /// At most this many low markers per day's comment.
    static let maxLowMarkers = 3

    static func rows(
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        observations: [ObservationEntry],
        interval: DateInterval,
        calendar: Calendar = .current,
        anchors: LogbookAnchors = .standard,
        lowThresholdMgdL: Double = 70
    ) -> [LogbookRow] {
        guard interval.duration > 0 else { return [] }

        // Active readings in the interval, sorted once for windowed lookup.
        let sortedReadings = readings
            .filter { $0.isActive && interval.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        let readingTimes = sortedReadings.map(\.timestamp)

        // Day buckets for everything that defines "this day has data".
        var readingsByDay: [Date: [GlucoseReading]] = [:]
        for r in sortedReadings {
            readingsByDay[calendar.startOfDay(for: r.timestamp), default: []].append(r)
        }
        var bolusByDay: [Date: [InsulinDose]] = [:]
        for dose in insulin where interval.contains(dose.timestamp) && isBolus(dose) {
            bolusByDay[calendar.startOfDay(for: dose.timestamp), default: []].append(dose)
        }
        var carbsByDay: [Date: [CarbEntry]] = [:]
        for entry in carbs where interval.contains(entry.timestamp) {
            carbsByDay[calendar.startOfDay(for: entry.timestamp), default: []].append(entry)
        }
        var observationsByDay: [Date: [ObservationEntry]] = [:]
        for o in observations where interval.contains(o.timestamp) {
            observationsByDay[calendar.startOfDay(for: o.timestamp), default: []].append(o)
        }

        let days = Set(readingsByDay.keys)
            .union(bolusByDay.keys)
            .union(carbsByDay.keys)
            .union(observationsByDay.keys)
            .sorted()   // ascending, so earlier days claim shared readings first

        var usedReadingIDs = Set<UUID>()
        var rows: [LogbookRow] = []

        for day in days {
            // Resolve the day's meal anchors: the user's own word first — the
            // earliest entry DECLARED as this meal anchors it at the moment it
            // was actually eaten (snacks never move a meal). The schedule /
            // default timetable is only the fallback for undeclared days.
            let base = [
                date(day, minutes: anchors.breakfastMinutes, calendar: calendar),
                date(day, minutes: anchors.lunchMinutes, calendar: calendar),
                date(day, minutes: anchors.dinnerMinutes, calendar: calendar),
            ]
            let dayCarbs = (carbsByDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            let declaredTypes: [MealType] = [.breakfast, .lunch, .dinner]
            let mealAnchors = (0..<3).map { meal -> Date in
                dayCarbs.first { $0.mealType == declaredTypes[meal] }?.timestamp ?? base[meal]
            }
            let bedtimeAnchor = date(day, minutes: anchors.bedtimeMinutes, calendar: calendar)

            // Glucose slots, chronological, each claiming its reading exactly
            // once. "Before" slots look backward from the meal; the rest keep
            // the symmetric window.
            let targets: [(LogbookGlucoseSlot, Date, TimeInterval, TimeInterval)] = [
                (.beforeBreakfast, mealAnchors[0], beforeMealLookback, beforeMealGrace),
                (.afterBreakfast, mealAnchors[0].addingTimeInterval(afterMealOffset), glucoseWindow, glucoseWindow),
                (.beforeLunch, mealAnchors[1], beforeMealLookback, beforeMealGrace),
                (.afterLunch, mealAnchors[1].addingTimeInterval(afterMealOffset), glucoseWindow, glucoseWindow),
                (.beforeDinner, mealAnchors[2], beforeMealLookback, beforeMealGrace),
                (.afterDinner, mealAnchors[2].addingTimeInterval(afterMealOffset), glucoseWindow, glucoseWindow),
                (.bedtime, bedtimeAnchor, glucoseWindow, glucoseWindow),
            ]
            var cells: [LogbookGlucoseSlot: LogbookCell] = [:]
            for (slot, target, lookback, lookahead) in targets {
                let cell = representative(
                    around: target, lookback: lookback, lookahead: lookahead,
                    readings: sortedReadings, times: readingTimes,
                    excluding: usedReadingIDs
                )
                if let id = cell.readingID { usedReadingIDs.insert(id) }
                cells[slot] = cell
            }

            // Insulin: each bolus dose counts toward its nearest meal anchor,
            // and only when it lands inside that anchor's ±90 min window.
            var mealUnits: [Double?] = [nil, nil, nil]
            var mealDoseIDs: [[UUID]] = [[], [], []]
            for dose in (bolusByDay[day] ?? []).sorted(by: { $0.timestamp < $1.timestamp }) {
                let meal = nearestIndex(of: dose.timestamp, in: mealAnchors)
                guard abs(dose.timestamp.timeIntervalSince(mealAnchors[meal])) <= insulinWindow else { continue }
                mealUnits[meal] = (mealUnits[meal] ?? 0) + dose.units
                mealDoseIDs[meal].append(dose.id)
            }

            let dayComment = comment(
                observations: observationsByDay[day] ?? [],
                readings: readingsByDay[day] ?? [],
                lowThresholdMgdL: lowThresholdMgdL,
                calendar: calendar
            )

            rows.append(LogbookRow(
                day: day,
                beforeBreakfast: cells[.beforeBreakfast]!,
                afterBreakfast: cells[.afterBreakfast]!,
                beforeLunch: cells[.beforeLunch]!,
                afterLunch: cells[.afterLunch]!,
                beforeDinner: cells[.beforeDinner]!,
                afterDinner: cells[.afterDinner]!,
                bedtime: cells[.bedtime]!,
                breakfastUnits: mealUnits[0], breakfastDoseIDs: mealDoseIDs[0],
                lunchUnits: mealUnits[1], lunchDoseIDs: mealDoseIDs[1],
                dinnerUnits: mealUnits[2], dinnerDoseIDs: mealDoseIDs[2],
                comment: dayComment
            ))
        }

        return Array(rows.reversed())   // newest first
    }

    // MARK: - Internals

    /// True for any dose that isn't basal — meal boluses, corrections and
    /// "other", excluding both the `.basal` context and basal insulin types.
    private static func isBolus(_ dose: InsulinDose) -> Bool {
        dose.doseContext != .basal && !dose.insulinType.isBasal
    }

    private static func date(_ day: Date, minutes: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: day) ?? day.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private static func nearestIndex(of timestamp: Date, in anchors: [Date]) -> Int {
        var best = 0
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for (index, anchor) in anchors.enumerated() {
            let distance = abs(timestamp.timeIntervalSince(anchor))
            if distance < bestDistance { best = index; bestDistance = distance }
        }
        return best
    }

    /// The representative reading for a slot: closest to `target` inside the
    /// slot's own (possibly asymmetric) window, preferring discrete (non-CGM)
    /// measurements, skipping readings already claimed by an earlier slot.
    private static func representative(
        around target: Date,
        lookback: TimeInterval,
        lookahead: TimeInterval,
        readings: [GlucoseReading],
        times: [Date],
        excluding used: Set<UUID>
    ) -> LogbookCell {
        let lower = target.addingTimeInterval(-lookback)
        let upper = target.addingTimeInterval(lookahead)

        // Binary search for the first reading at/after the window start; the
        // window is short, so the scan after it touches only a handful of rows.
        var lo = 0, hi = times.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < lower { lo = mid + 1 } else { hi = mid }
        }
        var candidates: [GlucoseReading] = []
        var index = lo
        while index < times.count && times[index] <= upper {
            let reading = readings[index]
            if !used.contains(reading.id) { candidates.append(reading) }
            index += 1
        }

        let discrete = candidates.filter { $0.measurementType != .cgm }
        let pool = discrete.isEmpty ? candidates : discrete
        let best = pool.min { a, b in
            let da = abs(a.timestamp.timeIntervalSince(target))
            let db = abs(b.timestamp.timeIntervalSince(target))
            if da != db { return da < db }
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.id.uuidString < b.id.uuidString   // total order for determinism
        }
        return LogbookCell(mgdL: best?.valueMgdL, readingID: best?.id, slotDate: target)
    }

    /// Joins the day's observation texts, then appends short low markers, e.g.
    /// "Stress; Low 47 at 02:51". Consecutive lows within `lowEpisodeGap` form
    /// one episode reported at its nadir; at most `maxLowMarkers` are listed.
    private static func comment(
        observations: [ObservationEntry],
        readings: [GlucoseReading],
        lowThresholdMgdL: Double,
        calendar: Calendar
    ) -> String {
        var parts: [String] = []
        for o in observations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let text = o.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                parts.append(text)
            } else if !o.tags.isEmpty {
                parts.append(o.tags.map(\.label).joined(separator: ", "))
            }
        }

        let lows = readings
            .filter { $0.valueMgdL < lowThresholdMgdL }
            .sorted { $0.timestamp < $1.timestamp }
        var episodes: [(nadir: Double, nadirAt: Date, lastAt: Date)] = []
        for low in lows {
            if let last = episodes.last, low.timestamp.timeIntervalSince(last.lastAt) <= lowEpisodeGap {
                episodes[episodes.count - 1].lastAt = low.timestamp
                if low.valueMgdL < last.nadir {
                    episodes[episodes.count - 1].nadir = low.valueMgdL
                    episodes[episodes.count - 1].nadirAt = low.timestamp
                }
            } else {
                episodes.append((low.valueMgdL, low.timestamp, low.timestamp))
            }
        }
        for episode in episodes.prefix(maxLowMarkers) {
            let hour = calendar.component(.hour, from: episode.nadirAt)
            let minute = calendar.component(.minute, from: episode.nadirAt)
            let time = String(format: "%02d:%02d", hour, minute)
            // Localized through the in-app language bundle so the auto-generated
            // register comments follow the chosen language, not just the device.
            parts.append(String(format: PrvitalString("Low %lld at %@"), Int(episode.nadir.rounded()), time))
        }
        if episodes.count > maxLowMarkers {
            parts.append(String(format: PrvitalString("+%lld more lows"), episodes.count - maxLowMarkers))
        }
        return parts.joined(separator: "; ")
    }
}
