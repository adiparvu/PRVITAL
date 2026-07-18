import XCTest
@testable import Prvital

/// Tests for the safety-critical insulin math: the IOB curve, its domain guard,
/// and the bolus suggestion breakdown.
final class InsulinMathTests: XCTestCase {

    // MARK: IOB curve

    func testIOBBoundaries() {
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 0, peak: 75, duration: 300), 1, accuracy: 1e-9)
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: -10, peak: 75, duration: 300), 1, accuracy: 1e-9)
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 300, peak: 75, duration: 300), 0, accuracy: 1e-9)
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 400, peak: 75, duration: 300), 0, accuracy: 1e-9)
    }

    func testIOBReferenceValues() {
        // Loop/oref exponential model, td=360, tp=75.
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 60, peak: 75, duration: 360), 0.779, accuracy: 0.01)
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 120, peak: 75, duration: 360), 0.450, accuracy: 0.01)
        XCTAssertEqual(InsulinMath.remainingFraction(minutes: 180, peak: 75, duration: 360), 0.208, accuracy: 0.01)
    }

    func testIOBMonotonicAndBounded() {
        var previous = 1.0 + 1e-6
        for minutes in stride(from: 0.0, through: 360, by: 5) {
            let value = InsulinMath.remainingFraction(minutes: minutes, peak: 75, duration: 360)
            XCTAssertFalse(value.isNaN)
            XCTAssertGreaterThanOrEqual(value, -1e-9)
            XCTAssertLessThanOrEqual(value, 1 + 1e-9)
            XCTAssertLessThanOrEqual(value, previous + 1e-9, "IOB must be non-increasing at \(minutes)m")
            previous = value
        }
    }

    func testDegeneratePeakFallsBackToLinear() {
        // peak == duration/2 makes tau infinite in the exponential model; the
        // guard must fall back to linear decay, never NaN or a spurious 0.
        let value = InsulinMath.remainingFraction(minutes: 120, peak: 120, duration: 240)
        XCTAssertFalse(value.isNaN)
        XCTAssertEqual(value, 0.5, accuracy: 1e-9) // 1 - 120/240
    }

    // MARK: Parameter validity

    func testIsValidGuards() {
        XCTAssertTrue(BolusParameters.default.isValid)

        var p = BolusParameters.default
        p.durationHours = 5; p.peakMinutes = 150   // 2*150 == 300, not < 300
        XCTAssertFalse(p.isValid, "peak == duration/2 must be invalid")
        p.peakMinutes = 149
        XCTAssertTrue(p.isValid)

        p = BolusParameters.default; p.carbRatio = 0
        XCTAssertFalse(p.isValid)
        p = BolusParameters.default; p.correctionFactor = 0
        XCTAssertFalse(p.isValid)
    }

    // MARK: Active insulin

    func testActiveInsulinCountsOnlyRapid() {
        let now = Date()
        let rapid = InsulinDose(units: 10, timestamp: now.addingTimeInterval(-1800), insulinType: .rapidActing)
        let basal = InsulinDose(units: 20, timestamp: now.addingTimeInterval(-1800), insulinType: .longActing)
        let iob = InsulinMath.activeInsulin(doses: [rapid, basal], at: now, parameters: .default)

        let fraction = InsulinMath.remainingFraction(minutes: 30, peak: 75, duration: 300)
        XCTAssertEqual(iob, 10 * fraction, accuracy: 1e-6, "basal must be excluded; rapid scaled by IOB fraction")
        XCTAssertGreaterThan(iob, 0)
    }

    func testActiveInsulinIgnoresExpiredAndFuture() {
        let now = Date()
        let expired = InsulinDose(units: 10, timestamp: now.addingTimeInterval(-6 * 3600), insulinType: .rapidActing)
        let future = InsulinDose(units: 10, timestamp: now.addingTimeInterval(600), insulinType: .rapidActing)
        let iob = InsulinMath.activeInsulin(doses: [expired, future], at: now, parameters: .default)
        XCTAssertEqual(iob, 0, accuracy: 1e-9)
    }

    // MARK: Bolus suggestion

    func testSuggestBolusBreakdown() {
        // default: carbRatio 10, ISF 50, target 110
        let estimate = InsulinMath.suggestBolus(carbs: 60, currentMgdL: 160, activeInsulin: 1,
                                                parameters: .default, thresholds: .standard)
        XCTAssertEqual(estimate.carbBolus, 6, accuracy: 1e-9)        // 60 / 10
        XCTAssertEqual(estimate.correctionBolus, 1, accuracy: 1e-9)  // (160 - 110) / 50
        XCTAssertEqual(estimate.activeInsulin, 1, accuracy: 1e-9)
        XCTAssertEqual(estimate.suggested, 6, accuracy: 1e-9)        // 6 + 1 - 1
    }

    func testSuggestBolusClampsToMaxWithWarning() {
        var p = BolusParameters.default; p.maxBolus = 5
        let estimate = InsulinMath.suggestBolus(carbs: 200, currentMgdL: 110, activeInsulin: 0,
                                                parameters: p, thresholds: .standard)
        XCTAssertEqual(estimate.suggested, 5, accuracy: 1e-9)
        XCTAssertFalse(estimate.warnings.isEmpty)
    }

    func testSuggestBolusLowGlucoseWarnsAndClampsToZero() {
        let estimate = InsulinMath.suggestBolus(carbs: 0, currentMgdL: 60, activeInsulin: 0,
                                                parameters: .default, thresholds: .standard)
        XCTAssertEqual(estimate.suggested, 0, accuracy: 1e-9)
        XCTAssertTrue(estimate.warnings.contains { $0.lowercased().contains("low") })
    }

    func testSuggestBolusNilGlucoseOmitsCorrection() {
        let estimate = InsulinMath.suggestBolus(carbs: 30, currentMgdL: nil, activeInsulin: 0,
                                                parameters: .default, thresholds: .standard)
        XCTAssertEqual(estimate.carbBolus, 3, accuracy: 1e-9)
        XCTAssertEqual(estimate.correctionBolus, 0, accuracy: 1e-9)
        XCTAssertFalse(estimate.warnings.isEmpty)
    }

    func testInvalidParametersNeverDivideByZero() {
        var p = BolusParameters.default; p.carbRatio = 0
        let estimate = InsulinMath.suggestBolus(carbs: 60, currentMgdL: 160, activeInsulin: 0,
                                                parameters: p, thresholds: .standard)
        XCTAssertFalse(estimate.carbBolus.isNaN)
        XCTAssertFalse(estimate.carbBolus.isInfinite)
        XCTAssertEqual(estimate.suggested, 0, accuracy: 1e-9)
        XCTAssertFalse(estimate.warnings.isEmpty)
    }
}
