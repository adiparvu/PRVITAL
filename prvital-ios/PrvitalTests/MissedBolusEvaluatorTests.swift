import XCTest
@testable import Prvital

final class MissedBolusEvaluatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func carb(_ id: String, minutesAgo: Double, grams: Double = 45) -> MissedBolusEvaluator.CarbEvent {
        .init(id: id, timestamp: now.addingTimeInterval(-minutesAgo * 60), grams: grams)
    }
    private func bolus(minutesAgo: Double) -> MissedBolusEvaluator.DoseEvent {
        .init(timestamp: now.addingTimeInterval(-minutesAgo * 60), isBolus: true)
    }
    private func basal(minutesAgo: Double) -> MissedBolusEvaluator.DoseEvent {
        .init(timestamp: now.addingTimeInterval(-minutesAgo * 60), isBolus: false)
    }
    private func point(minutesAgo: Double, _ mgdL: Double) -> MissedBolusEvaluator.Point {
        .init(timestamp: now.addingTimeInterval(-minutesAgo * 60), mgdL: mgdL)
    }

    func testMealWithoutBolusNudgesAfterGrace() {
        let (alert, state) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 30)], doses: [], points: [],
            state: .empty, now: now)
        XCTAssertEqual(alert?.kind, .loggedMeal)
        XCTAssertEqual(alert?.minutesAgo, 30)
        XCTAssertTrue(state.notifiedCarbIDs.contains("m1"))
    }

    func testFreshMealStaysQuietDuringGrace() {
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 10)], doses: [], points: [],
            state: .empty, now: now)
        XCTAssertNil(alert, "10 minutes is still pre-bolus territory")
    }

    func testPreBolusCoversTheMeal() {
        // Dosed 15 min before eating — classic pre-bolus, nothing to nag about.
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 30)], doses: [bolus(minutesAgo: 45)],
            points: [], state: .empty, now: now)
        XCTAssertNil(alert)
    }

    func testLateBolusCoversTheMeal() {
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 40)], doses: [bolus(minutesAgo: 5)],
            points: [], state: .empty, now: now)
        XCTAssertNil(alert)
    }

    func testBasalDoesNotCoverAMeal() {
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 30)], doses: [basal(minutesAgo: 20)],
            points: [], state: .empty, now: now)
        XCTAssertEqual(alert?.kind, .loggedMeal)
    }

    func testSnackBelowThresholdIsIgnored() {
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 30, grams: 10)], doses: [], points: [],
            state: .empty, now: now)
        XCTAssertNil(alert, "10 g is a snack, not a bolus-worthy meal")
    }

    func testEachMealNudgesOnlyOnce() {
        let first = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 30)], doses: [], points: [],
            state: .empty, now: now)
        let second = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 35)], doses: [], points: [],
            state: first.state, now: now.addingTimeInterval(300))
        XCTAssertNotNil(first.alert)
        XCTAssertNil(second.alert)
    }

    func testStaleMealIsLetGo() {
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [carb("m1", minutesAgo: 120)], doses: [], points: [],
            state: .empty, now: now)
        XCTAssertNil(alert, "past 90 minutes the advice is stale")
    }

    func testFastUnloggedClimbFires() {
        let points = [point(minutesAgo: 45, 130), point(minutesAgo: 30, 150),
                      point(minutesAgo: 15, 175), point(minutesAgo: 2, 195)]
        let (alert, state) = MissedBolusEvaluator.decide(
            carbs: [], doses: [], points: points, state: .empty, now: now)
        XCTAssertEqual(alert?.kind, .risingUnlogged)
        XCTAssertNotNil(state.lastRiseNotifiedAt)
    }

    func testClimbWithRecentBolusStaysQuiet() {
        let points = [point(minutesAgo: 45, 130), point(minutesAgo: 2, 195)]
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [], doses: [bolus(minutesAgo: 30)], points: points,
            state: .empty, now: now)
        XCTAssertNil(alert)
    }

    func testClimbBelowFloorStaysQuiet() {
        // Same 65 mg/dL climb, but topping out at 165 — in range, no nag.
        let points = [point(minutesAgo: 45, 100), point(minutesAgo: 2, 165)]
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [], doses: [], points: points, state: .empty, now: now)
        XCTAssertNil(alert)
    }

    func testSlowDriftStaysQuiet() {
        // +30 mg/dL over 50 min — dawn-phenomenon territory, not a meal.
        let points = [point(minutesAgo: 45, 160), point(minutesAgo: 2, 190)]
        let (alert, _) = MissedBolusEvaluator.decide(
            carbs: [], doses: [], points: points, state: .empty, now: now)
        XCTAssertNil(alert)
    }

    func testRiseCooldownBlocksARepeat() {
        let points = [point(minutesAgo: 45, 130), point(minutesAgo: 2, 195)]
        let first = MissedBolusEvaluator.decide(
            carbs: [], doses: [], points: points, state: .empty, now: now)
        let later = now.addingTimeInterval(30 * 60)
        let laterPoints = [MissedBolusEvaluator.Point(timestamp: later.addingTimeInterval(-45 * 60), mgdL: 150),
                           MissedBolusEvaluator.Point(timestamp: later.addingTimeInterval(-2 * 60), mgdL: 215)]
        let second = MissedBolusEvaluator.decide(
            carbs: [], doses: [], points: laterPoints, state: first.state, now: later)
        XCTAssertNotNil(first.alert)
        XCTAssertNil(second.alert, "2 h cooldown between rise nudges")
    }
}
