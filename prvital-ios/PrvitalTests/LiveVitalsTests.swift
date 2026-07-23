import XCTest
@testable import Prvital

final class LiveVitalsTests: XCTestCase {

    // Default parameters are valid (2·75 min < 5 h) so IOB computes.
    private let params = BolusParameters()

    func testInsulinCarbsAndTimings() {
        let now = Date()
        let insulin = [InsulinDose(units: 4, timestamp: now.addingTimeInterval(-30 * 60))] // rapid, 30 min ago
        let carbs = [CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-30 * 60))]

        let v = LiveVitals.make(
            latestReadingAt: now, sourceIsCGM: true, cgmCadenceMinutes: 5,
            insulin: insulin, carbs: carbs, bolus: params, now: now)

        XCTAssertTrue(v.hasInsulinOnBoard)
        XCTAssertTrue(v.hasCarbsOnBoard)
        XCTAssertEqual(v.minutesSinceBolus, 30)
        // Clears at dose + 5 h → 300 − 30 = 270 minutes from now.
        XCTAssertEqual(v.minutesToInsulinClear, 270)
        // Next Dexcom reading ≈ 5 minutes after the last one.
        XCTAssertEqual(v.minutesToNextReading, 5)
    }

    func testNextReadingOnlyForCGMSources() {
        let now = Date()
        let v = LiveVitals.make(
            latestReadingAt: now, sourceIsCGM: false, cgmCadenceMinutes: 5,
            insulin: [], carbs: [], bolus: params, now: now)
        XCTAssertNil(v.minutesToNextReading)
        XCTAssertFalse(v.hasInsulinOnBoard)
        XCTAssertFalse(v.hasCarbsOnBoard)
    }

    func testStaleCGMStreamHasNoNextReading() {
        let now = Date()
        // Last reading 20 min ago with a 5-min cadence → well beyond 2× cadence.
        let v = LiveVitals.make(
            latestReadingAt: now.addingTimeInterval(-20 * 60), sourceIsCGM: true,
            cgmCadenceMinutes: 5, insulin: [], carbs: [], bolus: params, now: now)
        XCTAssertNil(v.minutesToNextReading)
    }

    func testBasalDoseIsNotCountedAsBolus() {
        let now = Date()
        let insulin = [InsulinDose(units: 12, timestamp: now.addingTimeInterval(-60 * 60),
                                   insulinType: .longActing)]
        let v = LiveVitals.make(
            latestReadingAt: now, sourceIsCGM: true, cgmCadenceMinutes: 5,
            insulin: insulin, carbs: [], bolus: params, now: now)
        XCTAssertNil(v.minutesSinceBolus, "a basal dose is not a bolus")
    }
}
