import XCTest
@testable import Prvital

final class GlucoseProjectionTests: XCTestCase {

    private let thresholds = GlucoseThresholds.standard // 70…180

    func testImminentLow() {
        // 120, falling 2 mg/dL/min -> reaches 70 in 25 min (<= 30) -> low.
        let p = GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 120, velocityPerMinute: -2, thresholds: thresholds)
        XCTAssertEqual(p?.kind, .low)
        XCTAssertEqual(p?.minutes, 25)
    }

    func testImminentHigh() {
        // 150, rising 2 mg/dL/min -> reaches 180 in 15 min -> high.
        let p = GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 150, velocityPerMinute: 2, thresholds: thresholds)
        XCTAssertEqual(p?.kind, .high)
        XCTAssertEqual(p?.minutes, 15)
    }

    func testFlatTrendDoesNotWarn() {
        // Slope below the 1.0 mg/dL/min floor -> no warning even if it would cross.
        XCTAssertNil(GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 120, velocityPerMinute: -0.6, thresholds: thresholds))
    }

    func testTooFarAwayDoesNotWarn() {
        // 120 falling 1.2/min reaches 70 in ~41 min (> 30 horizon) -> nil.
        XCTAssertNil(GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 120, velocityPerMinute: -1.2, thresholds: thresholds))
    }

    func testMovingAwayFromRangeDoesNotWarn() {
        // Already above range and rising -> not heading toward the upper bound.
        XCTAssertNil(GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 200, velocityPerMinute: 3, thresholds: thresholds))
    }

    func testRisingWhileLowStillWarnsHighOnlyWhenApproaching() {
        // 60 (low) rising fast toward 70 is recovery, not a high warning.
        let p = GlucoseTrendAnalyzer.imminentProjection(
            currentMgdL: 60, velocityPerMinute: 3, thresholds: thresholds)
        // It should not flag a high (still below upper bound and far from it).
        XCTAssertNotEqual(p?.kind, .high)
    }
}
