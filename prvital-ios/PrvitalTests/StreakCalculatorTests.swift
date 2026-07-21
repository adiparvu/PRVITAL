import XCTest
@testable import Prvital

final class StreakCalculatorTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A fixed "today" at noon so day-boundary arithmetic is unambiguous.
    private var today: Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = 20; dc.hour = 12
        return cal.date(from: dc)!
    }

    /// A `DayTIR` for `daysAgo` before `today` with the given time-in-range.
    private func day(_ daysAgo: Int, tir: Double, count: Int = 12) -> DayTIR {
        let d = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: today))!
        return DayTIR(day: d, timeInRange: tir, readingCount: count)
    }

    private func evaluate(_ days: [DayTIR], target: Double = 0.70) -> StreakCalculator.StreakResult {
        StreakCalculator.evaluate(days: days, targetFraction: target, reference: today, calendar: cal)
    }

    // MARK: Empty / trivial

    func testEmptyInputIsNone() {
        XCTAssertEqual(evaluate([]), .none)
    }

    // MARK: Current streak

    func testTodayMetCountsToday() {
        let result = evaluate([day(0, tir: 0.80)])
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.best, 1)
        XCTAssertTrue(result.todayMet)
    }

    func testConsecutiveDaysEndingTodayStreak() {
        let result = evaluate([day(0, tir: 0.75), day(1, tir: 0.80), day(2, tir: 0.90)])
        XCTAssertEqual(result.current, 3)
        XCTAssertEqual(result.best, 3)
        XCTAssertTrue(result.todayMet)
    }

    func testTodayInProgressCountsFromYesterday() {
        // No entry for today at all → today is "in progress", streak carries from
        // yesterday's run and does not break.
        let result = evaluate([day(1, tir: 0.80), day(2, tir: 0.85)])
        XCTAssertEqual(result.current, 2)
        XCTAssertEqual(result.best, 2)
        XCTAssertFalse(result.todayMet)   // today has no data, so not "met"
    }

    func testTodayLoggedButBelowTargetBreaksCurrent() {
        // Today is present but short → current is 0, though the earlier run is
        // still the best on record.
        let result = evaluate([day(0, tir: 0.40), day(1, tir: 0.80), day(2, tir: 0.85)])
        XCTAssertEqual(result.current, 0)
        XCTAssertEqual(result.best, 2)
        XCTAssertFalse(result.todayMet)
    }

    func testMissingDayBreaksStreak() {
        // Gap at day-1 (no data): today counts alone, the older pair is the best.
        let result = evaluate([day(0, tir: 0.80), day(2, tir: 0.80), day(3, tir: 0.80)])
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.best, 2)
    }

    // MARK: Best streak

    func testBestStreakIsLongestRunWithGap() {
        // Runs: [today] = 1, and [day5,day6,day7] = 3 (older). Best is 3.
        let result = evaluate([
            day(0, tir: 0.80),
            day(5, tir: 0.80), day(6, tir: 0.80), day(7, tir: 0.80)
        ])
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.best, 3)
    }

    func testBestNeverBelowCurrent() {
        let result = evaluate([day(0, tir: 0.9), day(1, tir: 0.9), day(2, tir: 0.9), day(3, tir: 0.9)])
        XCTAssertEqual(result.current, 4)
        XCTAssertGreaterThanOrEqual(result.best, result.current)
    }

    // MARK: Target boundary

    func testExactTargetMeetsGoal() {
        let result = evaluate([day(0, tir: 0.70)], target: 0.70)
        XCTAssertEqual(result.current, 1)
        XCTAssertTrue(result.todayMet)
    }

    func testJustBelowTargetFails() {
        let result = evaluate([day(0, tir: 0.699)], target: 0.70)
        XCTAssertEqual(result.current, 0)
        XCTAssertFalse(result.todayMet)
    }

    // MARK: Robustness

    func testDefaultCalendarAndReferenceDoNotCrash() {
        // Exercises the production defaults (real "now" / current calendar).
        let anyDay = DayTIR(day: Date(), timeInRange: 0.8, readingCount: 10)
        _ = StreakCalculator.evaluate(days: [anyDay], targetFraction: 0.7)
    }
}
