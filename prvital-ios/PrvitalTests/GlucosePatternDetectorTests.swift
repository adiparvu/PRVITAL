import XCTest
@testable import Prvital

final class GlucosePatternDetectorTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func reading(_ mgdL: Double, hour: Int, day: Int) -> GlucoseReading {
        var c = DateComponents()
        c.year = 2024; c.month = 6; c.day = day; c.hour = hour; c.minute = 0
        return GlucoseReading(valueMgdL: mgdL, timestamp: calendar.date(from: c)!, source: .manual)
    }

    func testDayPeriodBoundaries() {
        func at(_ hour: Int) -> Date {
            var c = DateComponents(); c.year = 2024; c.month = 6; c.day = 1; c.hour = hour
            return calendar.date(from: c)!
        }
        XCTAssertTrue(DayPeriod.overnight.contains(at(0), calendar: calendar))
        XCTAssertTrue(DayPeriod.overnight.contains(at(5), calendar: calendar))
        XCTAssertFalse(DayPeriod.overnight.contains(at(6), calendar: calendar))
        XCTAssertTrue(DayPeriod.morning.contains(at(6), calendar: calendar))
        XCTAssertTrue(DayPeriod.afternoon.contains(at(12), calendar: calendar))
        XCTAssertTrue(DayPeriod.evening.contains(at(23), calendar: calendar))
    }

    func testOvernightLowsFlagged() {
        let readings = (0..<12).map { reading(55, hour: 2, day: $0 % 5 + 1) }
        let insights = GlucosePatternDetector.insights(readings, thresholds: .standard, calendar: calendar)
        XCTAssertEqual(insights.first?.period, .overnight)
        XCTAssertEqual(insights.first?.kind, .frequentLow)
        XCTAssertEqual(insights.first?.fraction ?? 0, 1, accuracy: 1e-9)
    }

    func testAfternoonHighsFlagged() {
        let readings = (0..<12).map { reading(220, hour: 14, day: $0 % 5 + 1) }
        let insights = GlucosePatternDetector.insights(readings, thresholds: .standard, calendar: calendar)
        XCTAssertEqual(insights.first?.period, .afternoon)
        XCTAssertEqual(insights.first?.kind, .frequentHigh)
    }

    func testInRangeProducesNoInsights() {
        let readings = (0..<12).map { reading(110, hour: 10, day: $0 % 5 + 1) }
        XCTAssertTrue(GlucosePatternDetector.insights(readings, thresholds: .standard, calendar: calendar).isEmpty)
    }

    func testTooFewReadingsIgnored() {
        let readings = (0..<5).map { reading(55, hour: 2, day: $0 + 1) }
        XCTAssertTrue(GlucosePatternDetector.insights(readings, thresholds: .standard, calendar: calendar).isEmpty)
    }

    func testLowsSortedBeforeHighs() {
        let lows = (0..<12).map { reading(55, hour: 2, day: $0 % 5 + 1) }
        let highs = (0..<12).map { reading(220, hour: 14, day: $0 % 5 + 1) }
        let insights = GlucosePatternDetector.insights(lows + highs, thresholds: .standard, calendar: calendar)
        XCTAssertEqual(insights.count, 2)
        XCTAssertEqual(insights.first?.kind, .frequentLow)
        XCTAssertEqual(insights.last?.kind, .frequentHigh)
    }
}
