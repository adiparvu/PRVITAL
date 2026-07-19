import XCTest
@testable import Prvital

final class ReboundDetectorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func r(_ minutes: Double, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: base.addingTimeInterval(minutes * 60), source: .manual)
    }

    func testDetectsReboundAfterLow() {
        // 60 low at 10 min, recovers at 20, spikes to 200 at 40 (within window).
        let readings = [r(0, 120), r(10, 60), r(15, 65), r(20, 100), r(40, 200)]
        let events = ReboundDetector.detect(readings, thresholds: .standard)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.lowMgdL ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(events.first?.highMgdL ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(events.first?.minutesLowToHigh, 30) // nadir at 10 → high at 40
    }

    func testNoReboundWhenStaysInRange() {
        let readings = [r(0, 120), r(10, 60), r(20, 100), r(40, 150)] // 150 < upper
        XCTAssertTrue(ReboundDetector.detect(readings, thresholds: .standard).isEmpty)
    }

    func testNoReboundWhenHighIsOutsideWindow() {
        let readings = [r(0, 120), r(10, 60), r(20, 100), r(160, 200)] // 200 at 160 min, past 120-min window from recovery(20)
        XCTAssertTrue(ReboundDetector.detect(readings, thresholds: .standard).isEmpty)
    }

    func testNoReboundWhenNeverRecovers() {
        let readings = [r(0, 120), r(10, 60), r(20, 55)] // ends still low
        XCTAssertTrue(ReboundDetector.detect(readings, thresholds: .standard).isEmpty)
    }

    func testStopsAtNextLowNoCrossAttribution() {
        // First low never spikes; a later low's high must not be attributed to the first.
        let readings = [r(0, 120), r(10, 60), r(20, 100), r(50, 55), r(60, 100), r(70, 190)]
        let events = ReboundDetector.detect(readings, thresholds: .standard)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.lowMgdL ?? 0, 55, accuracy: 1e-9) // only the second low rebounds
        XCTAssertEqual(events.first?.highMgdL ?? 0, 190, accuracy: 1e-9)
    }

    func testMultipleRebounds() {
        let readings = [
            r(0, 120), r(10, 60), r(20, 100), r(30, 200),   // rebound 1
            r(40, 120),
            r(50, 55), r(60, 100), r(70, 190),              // rebound 2
        ]
        let events = ReboundDetector.detect(readings, thresholds: .standard)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].lowMgdL, 60, accuracy: 1e-9)
        XCTAssertEqual(events[1].lowMgdL, 55, accuracy: 1e-9)
    }
}
