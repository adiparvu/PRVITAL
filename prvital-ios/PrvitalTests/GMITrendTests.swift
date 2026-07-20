import XCTest
@testable import Prvital

final class GMITrendTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ isoDay: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = isoDay; dc.hour = 12
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    private func gmi(_ mean: Double) -> Double { 3.31 + 0.02392 * mean }

    func testWeeklyPointsInChronologicalOrder() {
        // Three dates a week apart -> three weekly buckets. Provided out of order.
        let readings = [at(16, 183), at(2, 100), at(9, 154)]
        let points = GMITrend.weekly(readings, calendar: cal)
        XCTAssertEqual(points.count, 3)
        XCTAssertTrue(points[0].weekStart < points[1].weekStart)
        XCTAssertTrue(points[1].weekStart < points[2].weekStart)
        XCTAssertEqual(points[0].gmi, gmi(100), accuracy: 1e-9)
        XCTAssertEqual(points[1].gmi, gmi(154), accuracy: 1e-9)
        XCTAssertEqual(points[2].gmi, gmi(183), accuracy: 1e-9)
    }

    func testMeanWithinWeek() {
        // Two readings in the same week average before GMI.
        let points = GMITrend.weekly([at(2, 100), at(3, 200)], calendar: cal)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].gmi, gmi(150), accuracy: 1e-9)
        XCTAssertEqual(points[0].readingCount, 2)
    }

    func testMinReadingsPerWeekFilter() {
        // Week of the 2nd has 2 readings; week of the 9th has 1 -> dropped at min 2.
        let points = GMITrend.weekly([at(2, 100), at(3, 120), at(9, 150)], calendar: cal, minReadingsPerWeek: 2)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].readingCount, 2)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(GMITrend.weekly([], calendar: cal).isEmpty)
    }
}
