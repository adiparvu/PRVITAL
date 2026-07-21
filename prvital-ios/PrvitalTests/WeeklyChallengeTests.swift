import XCTest
@testable import Prvital

final class WeeklyChallengeTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(day: Int, hour: Int) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 6; dc.day = day; dc.hour = hour
        return cal.date(from: dc)!
    }

    // MARK: Engine

    func testProgressAndCompletion() {
        var i = ChallengeInputs()
        i.mealsLogged = 7
        XCTAssertTrue(WeeklyChallengeEngine.isComplete(.logMeals, i))
        i.tirGoalDays = 2
        let p = WeeklyChallengeEngine.progress(.tirGoalDays, i)
        XCTAssertEqual(p.current, 2)
        XCTAssertEqual(p.target, 4)
        XCTAssertFalse(WeeklyChallengeEngine.isComplete(.tirGoalDays, i))
    }

    func testCompletedCount() {
        var i = ChallengeInputs()
        i.mealsLogged = 10       // logMeals done
        i.activitiesLogged = 3   // logActivity done
        XCTAssertEqual(WeeklyChallengeEngine.completedCount(i), 2)
    }

    // MARK: Builder

    func testBuilderCountsThisWeek() {
        // now = Wednesday 2026-06-17 noon; week starts Monday 2026-06-15.
        let now = date(day: 17, hour: 12)

        // Eight in-range readings on Tuesday → a TIR-goal day and a steady day.
        var readings: [GlucoseReading] = []
        for h in 8..<16 {
            readings.append(GlucoseReading(valueMgdL: 120, timestamp: date(day: 16, hour: h), source: .manual))
        }
        let meals = [date(day: 15, hour: 8), date(day: 16, hour: 13), date(day: 17, hour: 8)]
            .map { CarbEntry(grams: 40, timestamp: $0) }
        let activity = [ActivityEntry(startTimestamp: date(day: 16, hour: 18), durationSeconds: 1800)]

        let inputs = ChallengeInputsBuilder.make(
            readings: readings, meals: meals, activity: activity,
            thresholds: .standard, goalFraction: 0.70, now: now, calendar: cal)

        XCTAssertEqual(inputs.mealsLogged, 3)
        XCTAssertEqual(inputs.activitiesLogged, 1)
        XCTAssertEqual(inputs.tirGoalDays, 1)
        XCTAssertEqual(inputs.steadyDays, 1)
        XCTAssertEqual(inputs.coverageDays, 0, "a handful of readings is far below full-day coverage")
    }

    func testLastWeeksDataExcluded() {
        let now = date(day: 17, hour: 12)  // week starts 2026-06-15
        let meals = [CarbEntry(grams: 40, timestamp: date(day: 10, hour: 8))]  // previous week
        let inputs = ChallengeInputsBuilder.make(
            readings: [], meals: meals, activity: [],
            thresholds: .standard, goalFraction: 0.70, now: now, calendar: cal)
        XCTAssertEqual(inputs.mealsLogged, 0)
    }
}
