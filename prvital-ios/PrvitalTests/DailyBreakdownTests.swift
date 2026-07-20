import XCTest
@testable import Prvital

final class DailyBreakdownTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func reading(day: Int, hour: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = hour
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    /// Six in-range or six out-of-range readings for a day (to clear the min).
    private func day(_ d: Int, inRange: Bool) -> [GlucoseReading] {
        (0..<6).map { reading(day: d, hour: $0, inRange ? 100 : 250) }
    }

    func testPerDayComputesTimeInRange() {
        let readings = day(10, inRange: true) + day(11, inRange: false)
        let days = DailyBreakdown.perDay(readings, thresholds: .standard, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].timeInRange, 1, accuracy: 1e-9)  // day 10 sorted first
        XCTAssertEqual(days[1].timeInRange, 0, accuracy: 1e-9)  // day 11
    }

    func testBestAndWorst() {
        let readings = day(10, inRange: true) + day(11, inRange: false)
        let days = DailyBreakdown.perDay(readings, thresholds: .standard, calendar: cal)
        XCTAssertEqual(DailyBreakdown.best(days)?.timeInRange ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(DailyBreakdown.worst(days)?.timeInRange ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(cal.component(.day, from: DailyBreakdown.best(days)!.day), 10)
        XCTAssertEqual(cal.component(.day, from: DailyBreakdown.worst(days)!.day), 11)
    }

    func testDaysBelowMinAreDropped() {
        // Day 10 has 6 readings (kept); day 11 has 2 (dropped at min 6).
        let readings = day(10, inRange: true) + [reading(day: 11, hour: 0, 100), reading(day: 11, hour: 1, 250)]
        let days = DailyBreakdown.perDay(readings, thresholds: .standard, calendar: cal)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(cal.component(.day, from: days[0].day), 10)
    }

    func testEmptyInputs() {
        XCTAssertTrue(DailyBreakdown.perDay([], thresholds: .standard, calendar: cal).isEmpty)
        XCTAssertNil(DailyBreakdown.best([]))
        XCTAssertNil(DailyBreakdown.worst([]))
    }
}
