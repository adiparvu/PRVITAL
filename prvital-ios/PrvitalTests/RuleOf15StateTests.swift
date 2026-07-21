import XCTest
@testable import Prvital

final class RuleOf15StateTests: XCTestCase {

    // Standard defaults: low threshold (targetLower) is 70 mg/dL.
    private let low = GlucoseThresholds.standard.targetLower

    func testStartsInTreatWithZeroRounds() {
        let state = RuleOf15State()
        XCTAssertEqual(state.phase, .treat)
        XCTAssertEqual(state.round, 0)
        XCTAssertFalse(state.isRepeatTreat)
    }

    func testTakeCarbsBeginsWaitAndCountsRound() {
        var state = RuleOf15State()
        state.takeCarbs()
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertEqual(state.round, 1)
    }

    func testRecheckAtOrAboveThresholdResolves() {
        var state = RuleOf15State()
        state.takeCarbs()
        state.recheck(mgdL: low, targetLowerMgdL: low)   // exactly at threshold counts as recovered
        XCTAssertEqual(state.phase, .resolved)
        XCTAssertEqual(state.round, 1)
    }

    func testRecheckStillLowLoopsBackToTreat() {
        var state = RuleOf15State()
        state.takeCarbs()
        state.recheck(mgdL: 62, targetLowerMgdL: low)
        XCTAssertEqual(state.phase, .treat)
        XCTAssertEqual(state.round, 1)          // round only increments on takeCarbs
        XCTAssertTrue(state.isRepeatTreat)      // reached treat again after a still-low recheck
    }

    func testSecondRoundThenRecovery() {
        var state = RuleOf15State()
        state.takeCarbs()                                   // round 1
        state.recheck(mgdL: 60, targetLowerMgdL: low)       // still low -> treat
        state.takeCarbs()                                   // round 2
        XCTAssertEqual(state.round, 2)
        state.recheck(mgdL: 95, targetLowerMgdL: low)       // recovered
        XCTAssertEqual(state.phase, .resolved)
        XCTAssertEqual(state.round, 2)
    }

    func testClockFormatsRemainingSeconds() {
        XCTAssertEqual(RuleOf15.clock(Double(RuleOf15.waitSeconds)), "15:00")
        XCTAssertEqual(RuleOf15.clock(0), "0:00")
        XCTAssertEqual(RuleOf15.clock(65), "1:05")
        // Rounds up so a partial second still shows the ceiling.
        XCTAssertEqual(RuleOf15.clock(59.2), "1:00")
        XCTAssertEqual(RuleOf15.clock(-5), "0:00")
    }
}
