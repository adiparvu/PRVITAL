import XCTest
@testable import Prvital

final class KetoneBandsTests: XCTestCase {

    func testNormalBelowThreshold() {
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 0.0), .normal)
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 0.59), .normal)
    }

    func testElevatedBand() {
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 0.6), .elevated)   // lower boundary
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 1.49), .elevated)
    }

    func testHighBand() {
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 1.5), .high)       // lower boundary
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 2.9), .high)
    }

    func testVeryHighBand() {
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 3.0), .veryHigh)   // lower boundary
        XCTAssertEqual(KetoneBands.band(forMmolPerL: 6.0), .veryHigh)
    }

    func testSeverityIncreasesWithBand() {
        XCTAssertEqual(KetoneBand.normal.severity, 0)
        XCTAssertLessThan(KetoneBand.elevated.severity, KetoneBand.high.severity)
        XCTAssertLessThan(KetoneBand.high.severity, KetoneBand.veryHigh.severity)
    }
}

final class SickDayAdvisorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(_ mgdL: Double, minutesAgo: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: now.addingTimeInterval(-minutesAgo * 60), source: .manual)
    }

    func testNoSuggestionWithTooFewReadings() {
        let readings = [reading(300, minutesAgo: 150), reading(300, minutesAgo: 30)]
        XCTAssertFalse(SickDayAdvisor.evaluate(readings: readings, now: now).shouldSuggest)
    }

    func testNoSuggestionWhenNotSustained() {
        // Three highs, but all within the last 20 minutes — a burst, not sustained.
        let readings = [
            reading(300, minutesAgo: 20),
            reading(300, minutesAgo: 10),
            reading(300, minutesAgo: 2),
        ]
        XCTAssertFalse(SickDayAdvisor.evaluate(readings: readings, now: now).shouldSuggest)
    }

    func testNoSuggestionWhenGlucoseNormal() {
        let readings = [
            reading(120, minutesAgo: 160),
            reading(130, minutesAgo: 90),
            reading(110, minutesAgo: 20),
        ]
        XCTAssertFalse(SickDayAdvisor.evaluate(readings: readings, now: now).shouldSuggest)
    }

    func testSuggestsOnSustainedHighs() {
        let readings = [
            reading(280, minutesAgo: 160),
            reading(300, minutesAgo: 90),
            reading(320, minutesAgo: 20),
        ]
        let s = SickDayAdvisor.evaluate(readings: readings, now: now)
        XCTAssertTrue(s.shouldSuggest)
        XCTAssertEqual(s.reason, .sustainedHighs)
        XCTAssertEqual(s.averageMgdL, 300, accuracy: 1e-9)
    }

    func testToleratesOneDipWhenMostlyHigh() {
        // 4 of 5 high (80%) over a sustained window — still suggests.
        let readings = [
            reading(300, minutesAgo: 165),
            reading(260, minutesAgo: 120),
            reading(190, minutesAgo: 80),   // a dip below 240
            reading(280, minutesAgo: 40),
            reading(310, minutesAgo: 10),
        ]
        XCTAssertTrue(SickDayAdvisor.evaluate(readings: readings, now: now).shouldSuggest)
    }

    func testDoesNotSuggestWhenTooManyDips() {
        // Only 3 of 5 high (60%) — below the 80% bar.
        let readings = [
            reading(300, minutesAgo: 165),
            reading(180, minutesAgo: 120),
            reading(170, minutesAgo: 80),
            reading(280, minutesAgo: 40),
            reading(310, minutesAgo: 10),
        ]
        XCTAssertFalse(SickDayAdvisor.evaluate(readings: readings, now: now).shouldSuggest)
    }
}
