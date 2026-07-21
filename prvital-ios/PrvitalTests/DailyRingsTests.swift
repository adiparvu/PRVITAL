import XCTest
@testable import Prvital

final class DailyRingsTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A fixed "now" at 12:00 UTC so "today" starts 12 hours earlier.
    private var now: Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 7; dc.day = 21; dc.hour = 12
        return cal.date(from: dc)!
    }

    private func reading(hour: Int, minute: Int = 0, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 7; dc.day = 21; dc.hour = hour; dc.minute = minute
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    private func rings(_ readings: [GlucoseReading], _ activity: [ActivityEntry] = []) -> DailyRings {
        DailyRings.make(
            readings: readings, activity: activity, thresholds: .standard,
            inRangeGoalFraction: 0.70, activeGoalMinutes: 30, coverageGoalFraction: 0.85,
            now: now, calendar: cal
        )
    }

    func testEmptyDayHasNoGlucose() {
        let r = rings([])
        XCTAssertFalse(r.hasGlucose)
        XCTAssertEqual(r.inRangeProgress, 0)
        XCTAssertEqual(r.metCount, 0)
    }

    func testInRangeProgressAgainstGoal() {
        // Four readings, three in range → 75% TIR, goal 70% → ring closed.
        let r = rings([reading(hour: 8, 120), reading(hour: 9, 100),
                       reading(hour: 10, 160), reading(hour: 11, 300)])
        XCTAssertTrue(r.hasGlucose)
        XCTAssertEqual(r.inRangeFraction, 0.75, accuracy: 0.0001)
        XCTAssertTrue(r.inRangeMet)
    }

    func testActiveRingFromLoggedMinutes() {
        let activity = [
            ActivityEntry(startTimestamp: reading(hour: 8, 0).timestamp, durationSeconds: 20 * 60),
            ActivityEntry(startTimestamp: reading(hour: 9, 0).timestamp, durationSeconds: 15 * 60),
        ]
        let r = rings([reading(hour: 8, 120)], activity)
        XCTAssertEqual(r.activeMinutes, 35)
        XCTAssertTrue(r.activeMet) // 35 ≥ 30
    }

    func testCoverageOverElapsedDay() {
        // 12 elapsed hours = 720 min → 144 expected samples at 5-min cadence.
        // 144 readings would be 100% coverage; use a handful → low coverage.
        let readings = (0..<12).map { reading(hour: $0, 120) }
        let r = rings(readings)
        XCTAssertLessThan(r.coverageFraction, 0.2)
        XCTAssertFalse(r.coverageMet)
    }

    func testYesterdaysReadingsExcluded() {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 7; dc.day = 20; dc.hour = 23
        let yesterday = GlucoseReading(valueMgdL: 120, timestamp: cal.date(from: dc)!, source: .manual)
        let r = rings([yesterday])
        XCTAssertFalse(r.hasGlucose, "readings before local midnight don't count toward today")
    }
}
