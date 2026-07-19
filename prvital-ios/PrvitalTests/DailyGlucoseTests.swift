import XCTest
@testable import Prvital

final class DailyGlucoseTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(day: Int, hour: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = hour
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    func testOnlyTodaysReadingsCount() {
        let reference = at(day: 10, hour: 12, 0).timestamp
        let readings = [
            at(day: 10, hour: 8, 100),  // today, in range
            at(day: 10, hour: 20, 120), // today, in range
            at(day: 9, hour: 23, 300),  // yesterday, excluded
            at(day: 11, hour: 1, 40),   // tomorrow, excluded
        ]
        let stats = DailyGlucose.today(readings, thresholds: .standard, reference: reference, calendar: cal)
        XCTAssertEqual(stats.readingCount, 2)
        XCTAssertEqual(stats.timeInRange, 1, accuracy: 1e-9)
        XCTAssertEqual(stats.average, 110, accuracy: 1e-9)
    }

    func testNoReadingsTodayIsEmpty() {
        let reference = at(day: 10, hour: 12, 0).timestamp
        let readings = [at(day: 9, hour: 8, 100), at(day: 11, hour: 8, 120)]
        let stats = DailyGlucose.today(readings, thresholds: .standard, reference: reference, calendar: cal)
        XCTAssertFalse(stats.hasGlucose)
        XCTAssertEqual(stats.readingCount, 0)
    }

    func testIncludesMidnightBoundary() {
        let reference = at(day: 10, hour: 12, 0).timestamp
        // Exactly local midnight is the first instant of "today".
        let readings = [at(day: 10, hour: 0, 90)]
        let stats = DailyGlucose.today(readings, thresholds: .standard, reference: reference, calendar: cal)
        XCTAssertEqual(stats.readingCount, 1)
    }
}
