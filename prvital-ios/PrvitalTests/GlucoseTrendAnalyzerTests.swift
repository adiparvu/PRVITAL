import XCTest
@testable import Prvital

final class GlucoseTrendAnalyzerTests: XCTestCase {

    func testRisingVelocityAndProjection() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: now.addingTimeInterval(-600), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now.addingTimeInterval(-300), source: .manual),
            GlucoseReading(valueMgdL: 140, timestamp: now, source: .manual),
        ]
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertNotNil(velocity)
        XCTAssertEqual(velocity!.mgdLPerMinute, 4, accuracy: 1e-6)
        XCTAssertEqual(velocity!.trend, .risingFast)
        XCTAssertEqual(velocity!.projectedMgdL(from: 140, minutes: 15), 200, accuracy: 1e-6)
    }

    func testFallingVelocity() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 140, timestamp: now.addingTimeInterval(-600), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now.addingTimeInterval(-300), source: .manual),
            GlucoseReading(valueMgdL: 100, timestamp: now, source: .manual),
        ]
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertEqual(velocity?.mgdLPerMinute ?? 0, -4, accuracy: 1e-6)
        XCTAssertEqual(velocity?.trend, .fallingFast)
    }

    func testStableVelocity() {
        let now = Date()
        let readings = (0..<3).map {
            GlucoseReading(valueMgdL: 110, timestamp: now.addingTimeInterval(Double(-$0 * 300)), source: .manual)
        }
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertEqual(velocity?.mgdLPerMinute ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(velocity?.trend, .stable)
    }

    func testInsufficientPointsReturnsNil() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: now.addingTimeInterval(-300), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now, source: .manual),
        ]
        XCTAssertNil(GlucoseTrendAnalyzer.velocity(readings, now: now))
    }

    func testOldReadingsExcludedFromWindow() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: now.addingTimeInterval(-40 * 60), source: .manual),
            GlucoseReading(valueMgdL: 110, timestamp: now.addingTimeInterval(-30 * 60), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now, source: .manual),
        ]
        // Only the last reading is within the 20-minute window.
        XCTAssertNil(GlucoseTrendAnalyzer.velocity(readings, now: now))
    }

    func testTrendCutoffs() {
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 3), .risingFast)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 2), .rising)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 1), .stable)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 0), .stable)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: -2), .falling)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: -3), .fallingFast)
    }

    func testProjectionClampsToZero() {
        let velocity = GlucoseVelocity(mgdLPerMinute: -10, trend: .fallingFast)
        XCTAssertEqual(velocity.projectedMgdL(from: 50, minutes: 30), 0, accuracy: 1e-6)
    }
}
