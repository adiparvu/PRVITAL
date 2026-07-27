import XCTest
@testable import Prvital

final class GlucoseForecastTests: XCTestCase {

    func testDampedProjectionIsLessThanLinear() {
        // Rising 2 mg/dL/min from 120 over 30 min. Linear would be +60 → 180.
        // Damping bends it below that.
        let f = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 2, horizonMinutes: 30)
        XCTAssertGreaterThan(f.projectedMgdL, 120)      // still rising
        XCTAssertLessThan(f.projectedMgdL, 180)         // but less than the linear 180
        XCTAssertLessThan(f.lowMgdL, f.projectedMgdL)
        XCTAssertGreaterThan(f.highMgdL, f.projectedMgdL)
        XCTAssertEqual(f.horizonMinutes, 30)
    }

    func testOnBoardWidensTheRange() {
        let plain = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 0, horizonMinutes: 30)
        let loaded = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 0,
                                             iob: 2, cob: 40, horizonMinutes: 30)
        let plainWidth = plain.highMgdL - plain.lowMgdL
        let loadedWidth = loaded.highMgdL - loaded.lowMgdL
        XCTAssertGreaterThan(loadedWidth, plainWidth, "insulin/carbs on board add uncertainty")
    }

    func testProjectionNeverGoesNegative() {
        let f = GlucoseForecast.project(currentMgdL: 60, velocityMgdLPerMin: -5, horizonMinutes: 60)
        XCTAssertGreaterThanOrEqual(f.projectedMgdL, 40)
        XCTAssertGreaterThanOrEqual(f.lowMgdL, 40)
    }

    func testReadingAgeExtendsTheProjection() {
        // "In 30 min" means 30 minutes from NOW — a 5-minute-old reading has
        // 35 minutes of travel ahead of it, not 30.
        let fresh = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 2, horizonMinutes: 30)
        let aged = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 2,
                                           minutesSinceReading: 5, horizonMinutes: 30)
        XCTAssertGreaterThan(aged.projectedMgdL, fresh.projectedMgdL)
        XCTAssertEqual(aged.horizonMinutes, 30, "the label still speaks in horizon minutes")
    }

    func testBandScalesWithMeasuredNoise() {
        // The band reflects the stream's own scatter, not a fixed pad.
        let quiet = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 0, sigmaMgdL: 3)
        let noisy = GlucoseForecast.project(currentMgdL: 120, velocityMgdLPerMin: 0, sigmaMgdL: 10)
        XCTAssertLessThan(quiet.highMgdL - quiet.lowMgdL, noisy.highMgdL - noisy.lowMgdL)
        XCTAssertLessThanOrEqual(quiet.highMgdL - quiet.lowMgdL, 24, "a quiet stream earns a tight band")
    }

    func testScreenshotScenarioBandIsHonestButUseful() {
        // The reported case: 138 mg/dL rising 1.2/min with 4.9 U IOB and 42 g
        // COB, reading 4 min old. The old fixed-pad formula said 126–205 (±39);
        // quadrature with real magnitudes lands ~±19 around ~167.
        let f = GlucoseForecast.project(
            currentMgdL: 138, velocityMgdLPerMin: 1.2, iob: 4.9, cob: 42,
            minutesSinceReading: 4, sigmaMgdL: 4, slopeSEPerMinute: 0.12, horizonMinutes: 30)
        XCTAssertEqual(f.projectedMgdL, 166.6, accuracy: 1.0)
        let half = (f.highMgdL - f.lowMgdL) / 2
        XCTAssertGreaterThanOrEqual(half, 10)
        XCTAssertLessThanOrEqual(half, 22, "the band must stay useful, not a blanket ±39")
    }
}
