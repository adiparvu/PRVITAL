import XCTest
@testable import Prvital

final class GlucoseAlertEvaluatorTests: XCTestCase {

    private func enabledPrefs(snooze: Int = 20) -> AlertPreferences {
        var p = AlertPreferences.default
        p.enabled = true
        p.snoozeMinutes = snooze
        return p
    }

    // MARK: Level mapping

    func testLevelMapping() {
        let t = GlucoseThresholds.standard // veryLow 54, target 70...180, high 250
        XCTAssertEqual(GlucoseAlertEvaluator.level(for: 40, thresholds: t), .urgentLow)
        XCTAssertEqual(GlucoseAlertEvaluator.level(for: 60, thresholds: t), .low)
        XCTAssertNil(GlucoseAlertEvaluator.level(for: 120, thresholds: t))
        XCTAssertEqual(GlucoseAlertEvaluator.level(for: 200, thresholds: t), .high)
        XCTAssertEqual(GlucoseAlertEvaluator.level(for: 300, thresholds: t), .urgentHigh)
    }

    // MARK: Firing

    func testFreshLowFires() {
        let now = Date()
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 60, timestamp: now), thresholds: .standard,
            preferences: enabledPrefs(), unit: .mgdL, last: .empty, now: now)
        XCTAssertEqual(d.alert?.level, .low)
        XCTAssertEqual(d.state.lastLevel, "low")
        XCTAssertEqual(d.state.lastFiredAt, now)
        XCTAssertEqual(d.state.lastReadingAt, now)
    }

    func testInRangeClearsLevelAndDoesNotFire() {
        let now = Date()
        let last = GlucoseAlertState(lastLevel: "low", lastFiredAt: now.addingTimeInterval(-600),
                                     lastReadingAt: now.addingTimeInterval(-300))
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 120, timestamp: now), thresholds: .standard,
            preferences: enabledPrefs(), unit: .mgdL, last: last, now: now)
        XCTAssertNil(d.alert)
        XCTAssertNil(d.state.lastLevel)
        XCTAssertEqual(d.state.lastReadingAt, now)
    }

    func testSameLevelWithinSnoozeIsSuppressed() {
        let now = Date()
        let last = GlucoseAlertState(lastLevel: "low", lastFiredAt: now.addingTimeInterval(-5 * 60),
                                     lastReadingAt: now.addingTimeInterval(-5 * 60))
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 62, timestamp: now), thresholds: .standard,
            preferences: enabledPrefs(snooze: 20), unit: .mgdL, last: last, now: now)
        XCTAssertNil(d.alert)
        XCTAssertEqual(d.state.lastLevel, "low")
        XCTAssertEqual(d.state.lastReadingAt, now)
    }

    func testSameLevelAfterSnoozeFires() {
        let now = Date()
        let last = GlucoseAlertState(lastLevel: "low", lastFiredAt: now.addingTimeInterval(-25 * 60),
                                     lastReadingAt: now.addingTimeInterval(-25 * 60))
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 62, timestamp: now), thresholds: .standard,
            preferences: enabledPrefs(snooze: 20), unit: .mgdL, last: last, now: now)
        XCTAssertEqual(d.alert?.level, .low)
    }

    func testEscalationBypassesSnooze() {
        let now = Date()
        let last = GlucoseAlertState(lastLevel: "low", lastFiredAt: now.addingTimeInterval(-5 * 60),
                                     lastReadingAt: now.addingTimeInterval(-5 * 60))
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 40, timestamp: now), thresholds: .standard,
            preferences: enabledPrefs(snooze: 20), unit: .mgdL, last: last, now: now)
        XCTAssertEqual(d.alert?.level, .urgentLow)
    }

    // MARK: Guards

    func testMasterDisabled() {
        let now = Date()
        var prefs = enabledPrefs(); prefs.enabled = false
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 40, timestamp: now), thresholds: .standard,
            preferences: prefs, unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
    }

    func testDisabledLevelDoesNotFire() {
        let now = Date()
        var prefs = enabledPrefs(); prefs.urgentHigh = false
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 300, timestamp: now), thresholds: .standard,
            preferences: prefs, unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
        XCTAssertNil(d.state.lastLevel)
    }

    func testStaleReadingDoesNotFire() {
        let now = Date()
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 40, timestamp: now.addingTimeInterval(-20 * 60)), thresholds: .standard,
            preferences: enabledPrefs(), unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
    }

    func testSameReadingNotAlertedTwice() {
        let now = Date()
        let ts = now.addingTimeInterval(-60)
        let last = GlucoseAlertState(lastLevel: "low", lastFiredAt: now.addingTimeInterval(-60), lastReadingAt: ts)
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 60, timestamp: ts), thresholds: .standard,
            preferences: enabledPrefs(), unit: .mgdL, last: last, now: now)
        XCTAssertNil(d.alert)
    }

    // MARK: Content

    func testAlertContent() {
        let urgent = GlucoseAlertEvaluator.makeAlert(level: .urgentLow, mgdL: 45, unit: .mgdL)
        XCTAssertEqual(urgent.title, "Urgent low glucose")
        XCTAssertTrue(urgent.body.contains("45"))

        let high = GlucoseAlertEvaluator.makeAlert(level: .urgentHigh, mgdL: 320, unit: .mgdL)
        XCTAssertEqual(high.level, .urgentHigh)
        XCTAssertTrue(high.body.contains("320"))
    }

    func testPreferencesLevelGate() {
        var p = AlertPreferences.default
        p.low = false
        XCTAssertFalse(p.isEnabled(.low))
        XCTAssertTrue(p.isEnabled(.urgentLow))
    }

    // MARK: Persistence filter

    private func persistentPrefs(minutes: Int) -> AlertPreferences {
        var p = enabledPrefs()
        p.persistenceMinutes = minutes
        return p
    }

    func testPersistenceHoldsTheFirstLowReading() {
        let now = Date()
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 60, timestamp: now), thresholds: .standard,
            preferences: persistentPrefs(minutes: 10), unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
        XCTAssertEqual(d.state.pendingLevel, "low")
        XCTAssertEqual(d.state.pendingSince, now)
    }

    func testPersistenceFiresOnceTheExcursionMatures() {
        let start = Date()
        var state = GlucoseAlertState.empty
        // t=0 arms, t=5 still waiting, t=10 fires.
        for minutes in [0.0, 5.0] {
            let t = start.addingTimeInterval(minutes * 60)
            let d = GlucoseAlertEvaluator.decide(
                reading: .init(mgdL: 60, timestamp: t), thresholds: .standard,
                preferences: persistentPrefs(minutes: 10), unit: .mgdL, last: state, now: t)
            XCTAssertNil(d.alert)
            state = d.state
        }
        let t = start.addingTimeInterval(10 * 60)
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 60, timestamp: t), thresholds: .standard,
            preferences: persistentPrefs(minutes: 10), unit: .mgdL, last: state, now: t)
        XCTAssertEqual(d.alert?.level, .low)
    }

    func testCompressionDipRecoversWithoutAlerting() {
        let start = Date()
        var state = GlucoseAlertState.empty
        let dip = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 62, timestamp: start), thresholds: .standard,
            preferences: persistentPrefs(minutes: 10), unit: .mgdL, last: state, now: start)
        XCTAssertNil(dip.alert)
        state = dip.state
        // Back in range five minutes later: pending clears, nothing ever fired.
        let t = start.addingTimeInterval(5 * 60)
        let recovered = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 95, timestamp: t), thresholds: .standard,
            preferences: persistentPrefs(minutes: 10), unit: .mgdL, last: state, now: t)
        XCTAssertNil(recovered.alert)
        XCTAssertNil(recovered.state.pendingLevel)
        XCTAssertNil(recovered.state.pendingSince)
    }

    func testUrgentLowBypassesPersistence() {
        let now = Date()
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 45, timestamp: now), thresholds: .standard,
            preferences: persistentPrefs(minutes: 15), unit: .mgdL, last: .empty, now: now)
        XCTAssertEqual(d.alert?.level, .urgentLow)
    }

    func testMaturedExcursionOnlyWaitsOutTheSnoozeOnRepeats() {
        let start = Date()
        // Already fired at t=0 with the pending marker carried through.
        let state = GlucoseAlertState(
            lastLevel: "low", lastFiredAt: start, lastReadingAt: start,
            pendingLevel: "low", pendingSince: start.addingTimeInterval(-10 * 60))
        var prefs = persistentPrefs(minutes: 10)
        prefs.snoozeMinutes = 20
        // After the snooze expires the repeat fires WITHOUT a second persistence wait.
        let t = start.addingTimeInterval(21 * 60)
        let d = GlucoseAlertEvaluator.decide(
            reading: .init(mgdL: 60, timestamp: t), thresholds: .standard,
            preferences: prefs, unit: .mgdL, last: state, now: t)
        XCTAssertEqual(d.alert?.level, .low)
    }
}
