import XCTest
@testable import Prvital

final class TIRTrendTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ day: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = 12
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    func testWeeklyTimeInRangeInOrder() {
        // Week of the 2nd: 100 & 250 -> TIR 0.5. Week of the 9th: 120 -> TIR 1.
        let readings = [at(9, 120), at(2, 100), at(3, 250)]
        let points = TIRTrend.weekly(readings, thresholds: .standard, calendar: cal)
        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points[0].weekStart < points[1].weekStart)
        XCTAssertEqual(points[0].timeInRange, 0.5, accuracy: 1e-9)
        XCTAssertEqual(points[0].readingCount, 2)
        XCTAssertEqual(points[1].timeInRange, 1, accuracy: 1e-9)
    }

    func testMinReadingsFilter() {
        let points = TIRTrend.weekly([at(2, 100), at(3, 120), at(9, 150)],
                                     thresholds: .standard, calendar: cal, minReadingsPerWeek: 2)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].readingCount, 2)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(TIRTrend.weekly([], thresholds: .standard, calendar: cal).isEmpty)
    }
}
