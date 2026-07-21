import Foundation

/// A rotating **weekly** goal that resets each week — the shorter-horizon
/// companion to the permanent achievements, to keep momentum going.
struct WeeklyChallenge: Identifiable, Equatable, Sendable {
    let id: WeeklyChallengeID
    let title: String
    let detail: String
    let symbol: String
    let target: Int
}

enum WeeklyChallengeID: String, CaseIterable, Sendable {
    case logMeals
    case logActivity
    case tirGoalDays
    case steadyDays
    case coverageDays
}

/// This week's numbers, summarised for the challenge engine.
struct ChallengeInputs: Equatable, Sendable {
    var mealsLogged = 0
    var activitiesLogged = 0
    /// Days this week that met the Time-in-Range goal.
    var tirGoalDays = 0
    /// Days mostly (≥ 50%) in the tight 70–140 range.
    var steadyDays = 0
    /// Days with strong (≥ 85%) sensor coverage.
    var coverageDays = 0
}

/// The weekly challenge catalogue and its pure progress rules.
enum WeeklyChallengeEngine {
    static let coverageDayThreshold = 0.85
    static let steadyDayFraction = 0.5

    static let catalog: [WeeklyChallenge] = [
        WeeklyChallenge(id: .tirGoalDays, title: String(localized: "On target"),
                        detail: String(localized: "Meet your time-in-range goal on 4 days."),
                        symbol: "target", target: 4),
        WeeklyChallenge(id: .steadyDays, title: String(localized: "Keep it steady"),
                        detail: String(localized: "Have 4 mostly-steady days (tight range)."),
                        symbol: "waveform.path.ecg", target: 4),
        WeeklyChallenge(id: .logMeals, title: String(localized: "Mealtime notes"),
                        detail: String(localized: "Log 7 meals this week."),
                        symbol: "fork.knife", target: 7),
        WeeklyChallenge(id: .logActivity, title: String(localized: "Get moving"),
                        detail: String(localized: "Log 3 activities this week."),
                        symbol: "figure.walk.motion", target: 3),
        WeeklyChallenge(id: .coverageDays, title: String(localized: "Stay connected"),
                        detail: String(localized: "5 days with strong sensor coverage."),
                        symbol: "dot.radiowaves.left.and.right", target: 5),
    ]

    static func challenge(_ id: WeeklyChallengeID) -> WeeklyChallenge {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    static func progress(_ id: WeeklyChallengeID, _ inputs: ChallengeInputs) -> (current: Int, target: Int) {
        let target = challenge(id).target
        let current: Int
        switch id {
        case .logMeals: current = inputs.mealsLogged
        case .logActivity: current = inputs.activitiesLogged
        case .tirGoalDays: current = inputs.tirGoalDays
        case .steadyDays: current = inputs.steadyDays
        case .coverageDays: current = inputs.coverageDays
        }
        return (min(max(current, 0), target), target)
    }

    static func isComplete(_ id: WeeklyChallengeID, _ inputs: ChallengeInputs) -> Bool {
        let p = progress(id, inputs)
        return p.current >= p.target
    }

    static func completedCount(_ inputs: ChallengeInputs) -> Int {
        WeeklyChallengeID.allCases.filter { isComplete($0, inputs) }.count
    }
}

/// Builds `ChallengeInputs` for the current week. Pure and deterministic.
enum ChallengeInputsBuilder {
    static let minReadingsPerDay = 6

    /// The start of the calendar week containing `now`.
    static func weekStart(for now: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    static func make(
        readings: [GlucoseReading],
        meals: [CarbEntry],
        activity: [ActivityEntry],
        thresholds: GlucoseThresholds,
        goalFraction: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ChallengeInputs {
        let start = weekStart(for: now, calendar: calendar)
        var inputs = ChallengeInputs()
        inputs.mealsLogged = meals.filter { $0.timestamp >= start && $0.timestamp <= now }.count
        inputs.activitiesLogged = activity.filter { $0.startTimestamp >= start && $0.startTimestamp <= now }.count

        // Bucket this week's readings by day.
        var byDay: [Date: [GlucoseReading]] = [:]
        for r in readings where r.isActive && r.timestamp >= start && r.timestamp <= now {
            byDay[calendar.startOfDay(for: r.timestamp), default: []].append(r)
        }

        for (dayStart, dayReadings) in byDay {
            // Coverage over the elapsed part of that day.
            let dayEnd = min(now, calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now)
            let elapsed = max(dayEnd.timeIntervalSince(dayStart), 60)
            let coverage = GlucoseCoverage.coverage(readingCount: dayReadings.count, window: elapsed)
            if coverage >= WeeklyChallengeEngine.coverageDayThreshold { inputs.coverageDays += 1 }

            guard dayReadings.count >= minReadingsPerDay else { continue }
            let stats = StatisticsEngine.glucose(dayReadings, thresholds: thresholds)
            if goalFraction > 0, stats.timeInRange >= goalFraction { inputs.tirGoalDays += 1 }
            if stats.timeInTightRange >= WeeklyChallengeEngine.steadyDayFraction { inputs.steadyDays += 1 }
        }
        return inputs
    }
}
