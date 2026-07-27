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

    func testBestVelocityPrefersTightWindowWhenSufficient() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: now.addingTimeInterval(-600), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now.addingTimeInterval(-300), source: .manual),
            GlucoseReading(valueMgdL: 140, timestamp: now, source: .manual),
        ]
        // All three points sit inside the 20-minute window, so bestVelocity uses it
        // and matches the tight-window rate exactly (4 mg/dL/min).
        XCTAssertEqual(GlucoseTrendAnalyzer.bestVelocity(readings, now: now)?.mgdLPerMinute ?? 0,
                       4, accuracy: 1e-6)
    }

    func testBestVelocityWidensWhenTightWindowIsShort() {
        let now = Date()
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: now.addingTimeInterval(-40 * 60), source: .manual),
            GlucoseReading(valueMgdL: 110, timestamp: now.addingTimeInterval(-30 * 60), source: .manual),
            GlucoseReading(valueMgdL: 120, timestamp: now, source: .manual),
        ]
        // The 20-minute window has only one point, but the 45-minute fallback has
        // all three — so bestVelocity recovers a rate the tight window couldn't.
        XCTAssertNil(GlucoseTrendAnalyzer.velocity(readings, now: now))
        XCTAssertNotNil(GlucoseTrendAnalyzer.bestVelocity(readings, now: now))
    }

    func testTrendCutoffs() {
        // Dexcom's flat arrow means |rate| < 1 mg/dL/min — so a shown rate of
        // +1.2 can never sit next to a "Stable" label again.
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 3), .risingFast)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 1.2), .rising)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 0.9), .stable)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: 0), .stable)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: -0.9), .stable)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: -1.2), .falling)
        XCTAssertEqual(GlucoseTrendAnalyzer.trend(forSlopePerMinute: -3), .fallingFast)
    }

    func testRecencyWeightingTracksATurn() {
        // Flat for 10 minutes, then rising 2 mg/dL/min over the last 10 — the
        // situation where a plain 20-min average (slope 1.0 here) lags the turn.
        // Recency weighting lands ~1.26 and the label agrees with the rate.
        let now = Date()
        let readings = [(-20.0, 110.0), (-15, 110), (-10, 110), (-5, 120), (0, 130)].map {
            GlucoseReading(valueMgdL: $0.1, timestamp: now.addingTimeInterval($0.0 * 60), source: .manual)
        }
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertEqual(velocity?.mgdLPerMinute ?? 0, 1.26, accuracy: 0.05)
        XCTAssertEqual(velocity?.trend, .rising)
    }

    func testCompressionLowOutlierDoesNotBendTheRate() {
        // A clean 1 mg/dL/min rise with one compression-low spike in the middle:
        // the robust pass drops the spike and recovers the true slope exactly.
        let now = Date()
        let readings = [(-20.0, 100.0), (-15, 105), (-10, 110), (-8, 70), (-5, 115), (0, 120)].map {
            GlucoseReading(valueMgdL: $0.1, timestamp: now.addingTimeInterval($0.0 * 60), source: .manual)
        }
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertEqual(velocity?.mgdLPerMinute ?? 0, 1.0, accuracy: 0.02)
        XCTAssertEqual(velocity?.sigmaMgdL ?? 99, 0, accuracy: 0.5, "outlier must be out of the fit")
    }

    func testCleanFitReportsTightUncertainty() {
        let now = Date()
        let readings = [(-10.0, 100.0), (-5, 120), (0, 140)].map {
            GlucoseReading(valueMgdL: $0.1, timestamp: now.addingTimeInterval($0.0 * 60), source: .manual)
        }
        let velocity = GlucoseTrendAnalyzer.velocity(readings, now: now)
        XCTAssertEqual(velocity?.sigmaMgdL ?? 99, 0, accuracy: 1e-6)
        XCTAssertEqual(velocity?.slopeSEPerMinute ?? 99, 0, accuracy: 1e-6)
    }

    func testProjectionClampsToZero() {
        let velocity = GlucoseVelocity(mgdLPerMinute: -10, trend: .fallingFast)
        XCTAssertEqual(velocity.projectedMgdL(from: 50, minutes: 30), 0, accuracy: 1e-6)
    }

    // MARK: minutesToReach

    func testMinutesToReachFallingTowardLow() throws {
        // 120 -> 70 at -2.5 mg/dL/min = 20 min
        XCTAssertEqual(try XCTUnwrap(GlucoseTrendAnalyzer.minutesToReach(70, from: 120, velocityPerMinute: -2.5)),
                       20, accuracy: 1e-9)
    }

    func testMinutesToReachRisingTowardHigh() throws {
        XCTAssertEqual(try XCTUnwrap(GlucoseTrendAnalyzer.minutesToReach(180, from: 150, velocityPerMinute: 3)),
                       10, accuracy: 1e-9)
    }

    func testMinutesToReachFlatIsNil() {
        XCTAssertNil(GlucoseTrendAnalyzer.minutesToReach(70, from: 120, velocityPerMinute: -0.2))
    }

    func testMinutesToReachMovingAwayIsNil() {
        // rising while the target is a low below -> moving away
        XCTAssertNil(GlucoseTrendAnalyzer.minutesToReach(70, from: 120, velocityPerMinute: 2))
    }

    func testMinutesToReachAlreadyPastIsNil() {
        // already below the target and still falling -> negative time
        XCTAssertNil(GlucoseTrendAnalyzer.minutesToReach(70, from: 60, velocityPerMinute: -2))
    }
}
