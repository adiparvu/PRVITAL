import XCTest
@testable import Prvital

final class JournalWeekSummaryTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    // A fixed anchor so the windows are deterministic (no Date() in the model).
    private var now: Date { Date(timeIntervalSince1970: 1_700_000_000) } // 2023-11-14

    private func day(_ agoDays: Int, tir: Double) -> JournalWeekSummary.Day {
        let start = cal.startOfDay(for: now)
        let d = cal.date(byAdding: .day, value: -agoDays, to: start)!
        return .init(day: d, timeInRange: tir)
    }

    func testNilWhenNoCurrentWeekDays() {
        // Only days older than a week → nothing to summarise now.
        let days = [day(9, tir: 0.8), day(11, tir: 0.7)]
        XCTAssertNil(JournalWeekSummary.make(days: days, now: now, calendar: cal))
    }

    func testAveragesThisWeekAndNoComparison() {
        let days = [day(0, tir: 0.80), day(1, tir: 0.60), day(2, tir: 0.70)]
        let s = JournalWeekSummary.make(days: days, now: now, calendar: cal)
        XCTAssertEqual(s?.timeInRange ?? 0, 0.70, accuracy: 1e-9)
        XCTAssertEqual(s?.dayCount, 3)
        XCTAssertEqual(s?.hasComparison, false)
        XCTAssertEqual(s?.trend, .steady)
        XCTAssertEqual(s?.delta ?? -1, 0, accuracy: 1e-9)
    }

    func testTrendUpWhenBetterThanPriorWeek() {
        let days = [day(1, tir: 0.85), day(2, tir: 0.85),   // this week ~0.85
                    day(8, tir: 0.60), day(9, tir: 0.60)]   // prior week ~0.60
        let s = JournalWeekSummary.make(days: days, now: now, calendar: cal)
        XCTAssertEqual(s?.trend, .up)
        XCTAssertEqual(s?.hasComparison, true)
        XCTAssertGreaterThan(s?.delta ?? 0, 0.2)
    }

    func testTrendDownWhenWorseThanPriorWeek() {
        let days = [day(1, tir: 0.55), day(8, tir: 0.85)]
        let s = JournalWeekSummary.make(days: days, now: now, calendar: cal)
        XCTAssertEqual(s?.trend, .down)
        XCTAssertLessThan(s?.delta ?? 0, 0)
    }

    func testSteadyWithinBand() {
        let days = [day(1, tir: 0.72), day(8, tir: 0.70)] // +2 points, within 3% band
        let s = JournalWeekSummary.make(days: days, now: now, calendar: cal)
        XCTAssertEqual(s?.trend, .steady)
        XCTAssertEqual(s?.hasComparison, true)
    }

    func testDailySeriesIsOldestToNewestAndThisWeekOnly() {
        // Passed newest-first; the series must come back oldest → newest and exclude
        // the prior-week day.
        let days = [day(0, tir: 0.90), day(2, tir: 0.50), day(1, tir: 0.70), day(9, tir: 0.10)]
        let s = JournalWeekSummary.make(days: days, now: now, calendar: cal)
        XCTAssertEqual(s?.dailyTimeInRange, [0.50, 0.70, 0.90]) // day -2, -1, 0
    }
}
