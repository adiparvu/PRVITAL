import XCTest
@testable import Prvital

final class OvernightStabilityTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func reading(hour: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = 10; dc.hour = hour
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    func testOnlyOvernightReadingsCount() {
        let readings = [
            reading(hour: 2, 100),  // overnight, in range
            reading(hour: 3, 60),   // overnight, low
            reading(hour: 12, 250), // daytime, excluded
            reading(hour: 20, 300), // daytime, excluded
        ]
        let stats = OvernightStability.analyze(readings, thresholds: .standard, calendar: cal)
        XCTAssertEqual(stats?.readingCount, 2)
        XCTAssertEqual(stats?.average ?? 0, 80, accuracy: 1e-9)       // (100+60)/2
        XCTAssertEqual(stats?.timeBelowRange ?? -1, 0.5, accuracy: 1e-9) // 60 is low
        XCTAssertEqual(stats?.timeInRange ?? -1, 0.5, accuracy: 1e-9)    // 100 in range
    }

    func testBoundaryHours() {
        // 0 is overnight; 6 is not.
        XCTAssertEqual(OvernightStability.analyze([reading(hour: 0, 90)], thresholds: .standard, calendar: cal)?.readingCount, 1)
        XCTAssertNil(OvernightStability.analyze([reading(hour: 6, 90)], thresholds: .standard, calendar: cal))
    }

    func testNoOvernightReadingsIsNil() {
        XCTAssertNil(OvernightStability.analyze([reading(hour: 14, 120)], thresholds: .standard, calendar: cal))
    }

    func testEmptyIsNil() {
        XCTAssertNil(OvernightStability.analyze([], thresholds: .standard, calendar: cal))
    }
}
