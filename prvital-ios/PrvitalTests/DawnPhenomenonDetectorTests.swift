import XCTest
@testable import Prvital

final class DawnPhenomenonDetectorTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A reading on a specific day-of-month and local hour (UTC), for determinism.
    private func reading(day: Int, hour: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = hour; dc.minute = 0
        let date = utc.date(from: dc)!
        return GlucoseReading(valueMgdL: mgdL, timestamp: date, source: .manual)
    }

    func testDetectsDawnRise() {
        var readings: [GlucoseReading] = []
        for day in 10...12 {
            readings.append(reading(day: day, hour: 3, 90))   // overnight nadir
            readings.append(reading(day: day, hour: 7, 130))  // morning level
        }
        let result = DawnPhenomenonDetector.analyze(readings, calendar: utc)
        XCTAssertEqual(result?.dayCount, 3)
        XCTAssertEqual(result?.medianRiseMgdL ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(result?.isPresent, true)
    }

    func testRiseBelowThresholdNotPresent() {
        var readings: [GlucoseReading] = []
        for day in 10...12 {
            readings.append(reading(day: day, hour: 3, 100))
            readings.append(reading(day: day, hour: 7, 108)) // rise 8 < 20
        }
        let result = DawnPhenomenonDetector.analyze(readings, calendar: utc)
        XCTAssertEqual(result?.dayCount, 3)
        XCTAssertEqual(result?.medianRiseMgdL ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(result?.isPresent, false)
    }

    func testInsufficientDaysNotPresent() {
        var readings: [GlucoseReading] = []
        for day in 10...11 { // only 2 qualifying days
            readings.append(reading(day: day, hour: 3, 90))
            readings.append(reading(day: day, hour: 7, 140))
        }
        let result = DawnPhenomenonDetector.analyze(readings, calendar: utc)
        XCTAssertEqual(result?.dayCount, 2)
        XCTAssertEqual(result?.isPresent, false) // 2 < minDays even though rise is large
    }

    func testDayWithoutMorningIsSkipped() {
        var readings: [GlucoseReading] = [reading(day: 9, hour: 3, 85)] // nadir only, no morning
        for day in 10...12 {
            readings.append(reading(day: day, hour: 3, 90))
            readings.append(reading(day: day, hour: 7, 130))
        }
        let result = DawnPhenomenonDetector.analyze(readings, calendar: utc)
        XCTAssertEqual(result?.dayCount, 3) // day 9 not counted
        XCTAssertEqual(result?.isPresent, true)
    }

    func testMorningLevelIsAveraged() {
        // One day; morning window has two readings averaging 120, nadir 80 -> rise 40.
        let readings = [
            reading(day: 10, hour: 2, 80),
            reading(day: 10, hour: 6, 110),
            reading(day: 10, hour: 8, 130),
        ]
        let result = DawnPhenomenonDetector.analyze(readings, calendar: utc)
        XCTAssertEqual(result?.dayCount, 1)
        XCTAssertEqual(result?.medianRiseMgdL ?? 0, 40, accuracy: 1e-9) // (110+130)/2 - 80
    }

    func testNoReadingsReturnsNil() {
        XCTAssertNil(DawnPhenomenonDetector.analyze([], calendar: utc))
    }

    func testMedianEvenCount() {
        XCTAssertEqual(DawnPhenomenonDetector.median([10, 20, 30, 40]), 25, accuracy: 1e-9)
        XCTAssertEqual(DawnPhenomenonDetector.median([30, 10, 40, 20]), 25, accuracy: 1e-9)
    }

    func testMedianOddCount() {
        XCTAssertEqual(DawnPhenomenonDetector.median([10, 50, 30]), 30, accuracy: 1e-9)
    }
}
