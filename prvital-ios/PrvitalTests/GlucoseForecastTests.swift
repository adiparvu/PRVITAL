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
}
