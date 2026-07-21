import XCTest
@testable import Prvital

final class TIRForecastTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = hour; dc.minute = minute
        return cal.date(from: dc)!
    }

    private func reading(day: Int, hour: Int, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: date(day: day, hour: hour), source: .manual)
    }

    private func reading(day: Int, minutesFromStart: Int, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: date(day: day, minute: minutesFromStart), source: .manual)
    }

    func testNoTodayReadingsReturnsNone() {
        let now = date(day: 10, hour: 12)
        let f = TIRForecastEngine.forecast(
            today: [], baseline: [reading(day: 9, hour: 12, 100)],
            thresholds: .standard, now: now, calendar: cal)
        XCTAssertFalse(f.hasData)
        XCTAssertEqual(f, .none)
    }

    func testCurrentFractionIsTodaysTIR() {
        let now = date(day: 10, hour: 12)
        let today = [reading(day: 10, hour: 1, 100), reading(day: 10, hour: 2, 300)] // 1 of 2 in range
        let f = TIRForecastEngine.forecast(
            today: today, baseline: [], thresholds: .standard, now: now, calendar: cal)
        XCTAssertEqual(f.currentFraction, 0.5, accuracy: 1e-9)
        XCTAssertTrue(f.hasData)
    }

    func testEarlyInDayBaselineDominates() {
        let now = date(day: 10, hour: 6) // 25% of the day elapsed
        let today = [reading(day: 10, hour: 1, 100), reading(day: 10, hour: 2, 100)] // TIR 1.0
        let baseline = [reading(day: 3, hour: 12, 300)] // TIR 0.0
        let f = TIRForecastEngine.forecast(
            today: today, baseline: baseline, thresholds: .standard, now: now, calendar: cal)
        // 0.25 * 1.0 + 0.75 * 0.0
        XCTAssertEqual(f.projectedFraction, 0.25, accuracy: 1e-9)
    }

    func testLaterInDayTodayDominates() {
        let now = date(day: 10, hour: 18) // 75% of the day elapsed
        let today = [reading(day: 10, hour: 1, 100), reading(day: 10, hour: 2, 100)] // TIR 1.0
        let baseline = [reading(day: 3, hour: 12, 300)] // TIR 0.0
        let f = TIRForecastEngine.forecast(
            today: today, baseline: baseline, thresholds: .standard, now: now, calendar: cal)
        // 0.75 * 1.0 + 0.25 * 0.0
        XCTAssertEqual(f.projectedFraction, 0.75, accuracy: 1e-9)
    }

    func testNoBaselineFallsBackToTodayTIR() {
        let now = date(day: 10, hour: 6)
        let today = [reading(day: 10, hour: 1, 100), reading(day: 10, hour: 2, 300)] // TIR 0.5
        let f = TIRForecastEngine.forecast(
            today: today, baseline: [], thresholds: .standard, now: now, calendar: cal)
        XCTAssertEqual(f.projectedFraction, 0.5, accuracy: 1e-9)
    }

    func testFutureReadingsAreIgnored() {
        let now = date(day: 10, hour: 6)
        // The hour-20 reading is in the future relative to `now` and must not count.
        let today = [reading(day: 10, hour: 1, 100), reading(day: 10, hour: 20, 300)]
        let f = TIRForecastEngine.forecast(
            today: today, baseline: [], thresholds: .standard, now: now, calendar: cal)
        XCTAssertEqual(f.currentFraction, 1.0, accuracy: 1e-9)
    }

    func testHighConfidenceWithDenseCoverage() {
        let now = date(day: 10, hour: 12) // ~144 readings expected for full coverage
        let today = (0..<120).map { reading(day: 10, minutesFromStart: $0 * 5, 100) }
        let f = TIRForecastEngine.forecast(
            today: today, baseline: [], thresholds: .standard, now: now, calendar: cal)
        XCTAssertEqual(f.confidence, .high)
    }

    func testLowConfidenceWithSparseCoverage() {
        let now = date(day: 10, hour: 12)
        let today = [reading(day: 10, hour: 3, 100), reading(day: 10, hour: 8, 110)]
        let f = TIRForecastEngine.forecast(
            today: today, baseline: [], thresholds: .standard, now: now, calendar: cal)
        XCTAssertEqual(f.confidence, .low)
    }
}
