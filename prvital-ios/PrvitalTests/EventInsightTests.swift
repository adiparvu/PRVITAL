import XCTest
@testable import Prvital

final class EventInsightTests: XCTestCase {

    private let params = BolusParameters()

    func testBeforeAfterAndDelta() {
        let now = Date()
        let event = now.addingTimeInterval(-3 * 3600) // 3h ago so the "after" exists
        let readings = [
            GlucoseReading(valueMgdL: 160, timestamp: event.addingTimeInterval(-5 * 60), source: .dexcom),   // before
            GlucoseReading(valueMgdL: 100, timestamp: event.addingTimeInterval(2 * 3600), source: .dexcom),   // ~2h after
        ]
        let insight = EventInsight.make(
            eventDate: event, excludingDoseID: nil,
            readings: readings, insulin: [], bolus: params, now: now)

        XCTAssertEqual(insight.glucoseBefore ?? 0, 160, accuracy: 1e-6)
        XCTAssertEqual(insight.glucoseAfter ?? 0, 100, accuracy: 1e-6)
        XCTAssertEqual(insight.deltaMgdL ?? 0, -60, accuracy: 1e-6)
        XCTAssertEqual(insight.afterElapsedMinutes, 120)
    }

    func testAfterMissingWhenNotEnoughTimeYet() {
        let now = Date()
        let event = now.addingTimeInterval(-20 * 60) // only 20 min ago — 2h "after" hasn't happened
        let readings = [
            GlucoseReading(valueMgdL: 150, timestamp: event.addingTimeInterval(-3 * 60), source: .dexcom),
        ]
        let insight = EventInsight.make(
            eventDate: event, excludingDoseID: nil,
            readings: readings, insulin: [], bolus: params, now: now)

        XCTAssertEqual(insight.glucoseBefore ?? 0, 150, accuracy: 1e-6)
        XCTAssertNil(insight.glucoseAfter)
        XCTAssertNil(insight.deltaMgdL)
    }

    func testIOBExcludesTheEventsOwnDose() {
        let now = Date()
        let event = now.addingTimeInterval(-30 * 60)
        let ownDose = InsulinDose(units: 6, timestamp: event)
        let priorDose = InsulinDose(units: 3, timestamp: event.addingTimeInterval(-60 * 60)) // 1h earlier
        let insight = EventInsight.make(
            eventDate: event, excludingDoseID: ownDose.id,
            readings: [], insulin: [ownDose, priorDose], bolus: params, now: now)

        // Only the prior dose contributes to on-board insulin at the event moment.
        XCTAssertNotNil(insight.iobBefore)
        XCTAssertGreaterThan(insight.iobBefore ?? 0, 0)
        XCTAssertLessThan(insight.iobBefore ?? 99, 3) // less than the full prior 3 U (some decayed)
    }
}
