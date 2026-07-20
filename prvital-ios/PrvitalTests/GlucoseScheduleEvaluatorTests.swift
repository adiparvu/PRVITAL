import XCTest
@testable import Prvital

final class GlucoseScheduleEvaluatorTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = 10; dc.hour = hour; dc.minute = minute
        return cal.date(from: dc)!
    }

    private func schedule(_ minutes: [Int]) -> GlucoseSchedule {
        GlucoseSchedule(remindersEnabled: false, slots: minutes.map {
            GlucoseLogSlot(label: "Slot", minutesFromMidnight: $0)
        })
    }

    func testDoneWhenReadingNearSlot() {
        // Slot at 07:00, a reading at 07:20, now 09:00 -> done.
        let s = schedule([7 * 60])
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [date(7, 20)], now: date(9), calendar: cal)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].state, .done)
        XCTAssertNotNil(statuses[0].matchedReading)
    }

    func testDueWhenPastWithNoReading() {
        // Slot at 07:00, no reading, now 09:00 (past the 90-min window) -> due.
        let s = schedule([7 * 60])
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [], now: date(9), calendar: cal)
        XCTAssertEqual(statuses[0].state, .due)
    }

    func testUpcomingWhenSlotInFuture() {
        // Slot at 18:00, now 09:00 -> upcoming.
        let s = schedule([18 * 60])
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [], now: date(9), calendar: cal)
        XCTAssertEqual(statuses[0].state, .upcoming)
    }

    func testWithinWindowStillUpcomingNotDue() {
        // Slot at 09:00, now 09:30 (inside 90-min window), no reading -> upcoming.
        let s = schedule([9 * 60])
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [], now: date(9, 30), calendar: cal)
        XCTAssertEqual(statuses[0].state, .upcoming)
    }

    func testReadingFromAnotherDayDoesNotCount() {
        let s = schedule([7 * 60])
        var dc = DateComponents(); dc.year = 2026; dc.month = 3; dc.day = 9; dc.hour = 7
        let yesterday = cal.date(from: dc)!
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [yesterday], now: date(9), calendar: cal)
        XCTAssertEqual(statuses[0].state, .due)
    }

    func testProgressCounts() {
        let s = schedule([7 * 60, 12 * 60, 18 * 60])
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [date(7, 5)], now: date(13), calendar: cal)
        let p = GlucoseScheduleEvaluator.progress(statuses)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.total, 3)
    }

    func testDisabledSlotsExcluded() {
        var s = schedule([7 * 60, 12 * 60])
        s.slots[1].enabled = false
        let statuses = GlucoseScheduleEvaluator.status(
            schedule: s, readingTimes: [], now: date(13), calendar: cal)
        XCTAssertEqual(statuses.count, 1)
    }
}
