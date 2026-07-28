import Foundation

/// How life context correlates with glucose: for each quick tag used in the
/// window, time-in-range on the days carrying that tag vs the days without it.
struct TagImpact: Equatable, Sendable, Identifiable {
    let tag: ObservationTag
    /// Calendar days in the window carrying this tag (with glucose data).
    let dayCount: Int
    /// TIR (0...1) over readings on tagged days.
    let taggedTIR: Double
    /// TIR (0...1) over readings on the window's *other* days; nil when every
    /// glucose day carries the tag (nothing to compare against).
    let untaggedTIR: Double?

    var id: String { tag.rawValue }
    /// Tagged minus untagged, in TIR points (−1…1); nil without a comparison.
    var delta: Double? { untaggedTIR.map { taggedTIR - $0 } }
}

/// A day is "tagged" when any entry that day — glucose reading, meal or
/// observation — carries the tag. Comparing whole days (not just the tagged
/// hours) is deliberate: stress or illness shapes the day, not the minute.
enum TagImpactAnalyzer {

    /// Minimum tagged days with glucose before a comparison is worth showing.
    static let minTaggedDays = 2

    static func analyze(
        readings: [GlucoseReading],
        carbs: [CarbEntry],
        observations: [ObservationEntry],
        thresholds: GlucoseThresholds,
        calendar: Calendar = .current,
        maxTags: Int = 4
    ) -> [TagImpact] {
        // Which days carry which tags.
        var tagsByDay: [Date: Set<ObservationTag>] = [:]
        func mark(_ timestamp: Date, _ tags: [ObservationTag]) {
            guard !tags.isEmpty else { return }
            tagsByDay[calendar.startOfDay(for: timestamp), default: []].formUnion(tags)
        }
        for reading in readings where reading.isActive { mark(reading.timestamp, reading.tags) }
        for entry in carbs { mark(entry.timestamp, entry.tags) }
        for note in observations { mark(note.timestamp, note.tags) }
        guard !tagsByDay.isEmpty else { return [] }

        // Per-day in-range/total counts over active readings.
        var inRangeByDay: [Date: (inRange: Int, total: Int)] = [:]
        for reading in readings where reading.isActive {
            let day = calendar.startOfDay(for: reading.timestamp)
            var counts = inRangeByDay[day] ?? (0, 0)
            counts.total += 1
            if thresholds.zone(forMgdL: reading.valueMgdL, at: reading.timestamp) == .inRange {
                counts.inRange += 1
            }
            inRangeByDay[day] = counts
        }
        let glucoseDays = Set(inRangeByDay.keys)
        guard !glucoseDays.isEmpty else { return [] }

        let allTags = Set(tagsByDay.values.flatMap { $0 })
        var impacts: [TagImpact] = []
        for tag in allTags {
            let taggedDays = Set(tagsByDay.filter { $0.value.contains(tag) }.keys)
                .intersection(glucoseDays)
            guard taggedDays.count >= minTaggedDays else { continue }
            let otherDays = glucoseDays.subtracting(taggedDays)

            func tir(over days: Set<Date>) -> Double? {
                let counts = days.compactMap { inRangeByDay[$0] }
                let total = counts.reduce(0) { $0 + $1.total }
                guard total > 0 else { return nil }
                return Double(counts.reduce(0) { $0 + $1.inRange }) / Double(total)
            }
            guard let tagged = tir(over: taggedDays) else { continue }
            impacts.append(TagImpact(
                tag: tag, dayCount: taggedDays.count,
                taggedTIR: tagged, untaggedTIR: tir(over: otherDays)))
        }
        return impacts
            .sorted { ($0.dayCount, $0.id) > ($1.dayCount, $1.id) }
            .prefix(maxTags)
            .map { $0 }
    }
}
