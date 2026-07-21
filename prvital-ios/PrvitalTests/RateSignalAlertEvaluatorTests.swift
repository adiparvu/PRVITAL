import XCTest
@testable import Prvital

final class RateSignalAlertEvaluatorTests: XCTestCase {

    private func prefs(rise: Bool = false, fall: Bool = false, signal: Bool = false,
                       rate: Double = 3.0, signalMin: Int = 25, snooze: Int = 20) -> AlertPreferences {
        var p = AlertPreferences.default
        p.enabled = true
        p.riseRateEnabled = rise
        p.fallRateEnabled = fall
        p.rateThresholdPerMinute = rate
        p.signalLossEnabled = signal
        p.signalLossMinutes = signalMin
        p.snoozeMinutes = snooze
        return p
    }

    // MARK: - AlertPreferences tolerant decoding (safety: no silent reset)

    func testDecodesLegacyJSONWithoutNewKeys() throws {
        // A settings blob saved before the rate/signal fields existed.
        let legacy = """
        {"enabled":true,"urgentLow":true,"low":false,"high":true,"urgentHigh":true,"snoozeMinutes":30}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlertPreferences.self, from: legacy)
        // Existing choices preserved…
        XCTAssertTrue(decoded.enabled)
        XCTAssertFalse(decoded.low)
        XCTAssertEqual(decoded.snoozeMinutes, 30)
        // …new fields take their safe defaults.
        XCTAssertFalse(decoded.riseRateEnabled)
        XCTAssertFalse(decoded.fallRateEnabled)
        XCTAssertFalse(decoded.signalLossEnabled)
        XCTAssertEqual(decoded.rateThresholdPerMinute, 3.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.signalLossMinutes, 25)
    }

    func testRoundTripEncodeDecode() throws {
        let original = prefs(rise: true, fall: true, signal: true, rate: 2.5, signalMin: 30)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlertPreferences.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Rate of change

    func testRisingFastFires() {
        let now = Date()
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 150, perMinute: 3.2, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true), unit: .mgdL, last: .empty, now: now)
        XCTAssertEqual(d.alert?.kind, .rising)
        XCTAssertEqual(d.state.lastKind, "rising")
        XCTAssertEqual(d.state.lastReadingAt, now)
    }

    func testFallingFastFiresOnlyWhenEnabled() {
        let now = Date()
        // Falling fast but only the rise toggle is on → no alert.
        let none = RateOfChangeAlertEvaluator.decide(
            mgdL: 90, perMinute: -4.0, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true, fall: false), unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(none.alert)

        let fires = RateOfChangeAlertEvaluator.decide(
            mgdL: 90, perMinute: -4.0, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(fall: true), unit: .mgdL, last: .empty, now: now)
        XCTAssertEqual(fires.alert?.kind, .falling)
    }

    func testBelowThresholdDoesNotFire() {
        let now = Date()
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 150, perMinute: 1.5, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true, fall: true), unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
        XCTAssertNil(d.state.lastKind)
        XCTAssertEqual(d.state.lastReadingAt, now)
    }

    func testSameDirectionSnoozes() {
        let now = Date()
        let last = RateAlertState(lastKind: "rising", lastFiredAt: now.addingTimeInterval(-300),
                                  lastReadingAt: now.addingTimeInterval(-300))
        let newReading = now // different timestamp than last reading
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 170, perMinute: 3.5, timestamp: newReading, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true, snooze: 20), unit: .mgdL, last: last, now: now)
        XCTAssertNil(d.alert, "still rising within the snooze window shouldn't re-fire")
        XCTAssertEqual(d.state.lastReadingAt, newReading)
    }

    func testDirectionChangeBypassesSnooze() {
        let now = Date()
        let last = RateAlertState(lastKind: "rising", lastFiredAt: now.addingTimeInterval(-60),
                                  lastReadingAt: now.addingTimeInterval(-300))
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 80, perMinute: -3.5, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true, fall: true, snooze: 20), unit: .mgdL, last: last, now: now)
        XCTAssertEqual(d.alert?.kind, .falling, "a change of direction should alert immediately")
    }

    func testSameReadingNotAlertedTwice() {
        let now = Date()
        let last = RateAlertState(lastKind: nil, lastFiredAt: nil, lastReadingAt: now)
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 150, perMinute: 4.0, timestamp: now, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true), unit: .mgdL, last: last, now: now)
        XCTAssertNil(d.alert)
    }

    func testStaleReadingIgnored() {
        let now = Date()
        let old = now.addingTimeInterval(-20 * 60) // older than maxReadingAge
        let d = RateOfChangeAlertEvaluator.decide(
            mgdL: 150, perMinute: 4.0, timestamp: old, thresholdPerMinute: 3.0,
            preferences: prefs(rise: true), unit: .mgdL, last: .empty, now: now)
        XCTAssertNil(d.alert)
    }

    // MARK: - Signal loss

    func testSignalLossFiresAfterWindow() {
        let now = Date()
        let lastReading = now.addingTimeInterval(-30 * 60)
        let d = SignalLossAlertEvaluator.decide(
            lastReadingAt: lastReading, preferences: prefs(signal: true, signalMin: 25),
            last: .empty, now: now)
        XCTAssertNotNil(d.alert)
        XCTAssertEqual(d.state.firedForReadingAt, lastReading)
    }

    func testSignalLossFiresOncePerGap() {
        let now = Date()
        let lastReading = now.addingTimeInterval(-40 * 60)
        let already = SignalLossState(firedForReadingAt: lastReading)
        let d = SignalLossAlertEvaluator.decide(
            lastReadingAt: lastReading, preferences: prefs(signal: true, signalMin: 25),
            last: already, now: now)
        XCTAssertNil(d.alert, "the same gap should only alert once")
        XCTAssertEqual(d.state.firedForReadingAt, lastReading)
    }

    func testFreshDataResetsSignalState() {
        let now = Date()
        let lastReading = now.addingTimeInterval(-5 * 60) // within window
        let prior = SignalLossState(firedForReadingAt: now.addingTimeInterval(-90 * 60))
        let d = SignalLossAlertEvaluator.decide(
            lastReadingAt: lastReading, preferences: prefs(signal: true, signalMin: 25),
            last: prior, now: now)
        XCTAssertNil(d.alert)
        XCTAssertNil(d.state.firedForReadingAt, "fresh data clears the fired anchor")
    }

    func testSignalLossOffDoesNothing() {
        let now = Date()
        let d = SignalLossAlertEvaluator.decide(
            lastReadingAt: now.addingTimeInterval(-60 * 60),
            preferences: prefs(signal: false), last: .empty, now: now)
        XCTAssertNil(d.alert)
    }
}
