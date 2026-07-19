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
}
