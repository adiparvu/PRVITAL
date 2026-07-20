import XCTest
@testable import Prvital

final class WeekdayWeekendComparatorTests: XCTestCase {

    // Gregorian/UTC so weekend detection is deterministic. In Jan 2024:
    // the 6th is Saturday, 7th Sunday, 8th Monday, 9th Tuesday.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func reading(day: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = day; dc.hour = 12
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    func testSplitsWeekdayAndWeekend() {
        let readings = [
            reading(day: 6, 250), reading(day: 7, 250),  // Sat, Sun -> out of range
            reading(day: 8, 100), reading(day: 9, 100),  // Mon, Tue -> in range
        ]
        let stats = WeekdayWeekendComparator.compare(readings, thresholds: .standard, calendar: cal)
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.weekdayTimeInRange ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(stats?.weekendTimeInRange ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(stats?.weekdayAverageMgdL ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(stats?.weekendAverageMgdL ?? 0, 250, accuracy: 1e-9)
    }

    func testNilWhenOnlyWeekdays() {
        let readings = [reading(day: 8, 100), reading(day: 9, 120)]
        XCTAssertNil(WeekdayWeekendComparator.compare(readings, thresholds: .standard, calendar: cal))
    }

    func testNilWhenOnlyWeekend() {
        let readings = [reading(day: 6, 100), reading(day: 7, 120)]
        XCTAssertNil(WeekdayWeekendComparator.compare(readings, thresholds: .standard, calendar: cal))
    }

    func testNilWhenEmpty() {
        XCTAssertNil(WeekdayWeekendComparator.compare([], thresholds: .standard, calendar: cal))
    }
}
