import XCTest
@testable import Prvital

/// Pure-logic tests for the critical-low "repeat until acknowledged"
/// escalation planner: the repeat schedule, the identifier scheme used to arm
/// and cancel batches, and the acknowledgment rules.
final class CriticalAlarmTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func prefs(enabled: Bool = true, minutes: Int = 5, repeats: Int = 6) -> CriticalAlarmPreferences {
        var p = CriticalAlarmPreferences()
        p.escalationEnabled = enabled
        p.repeatMinutes = minutes
        p.maxRepeats = repeats
        return p
    }

    // MARK: Schedule planning

    func testDisabledEscalationPlansNothing() {
        XCTAssertTrue(CriticalAlarmPlanner.schedule(from: prefs(enabled: false)).isEmpty)
    }

    func testDefaultScheduleIsSixRepeatsEveryFiveMinutes() {
        let steps = CriticalAlarmPlanner.schedule(from: prefs())
        XCTAssertEqual(steps.map(\.index), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(steps.map(\.delaySeconds), [300, 600, 900, 1200, 1500, 1800])
    }

    func testTenMinuteCadenceWithThreeRepeats() {
        let steps = CriticalAlarmPlanner.schedule(from: prefs(minutes: 10, repeats: 3))
        XCTAssertEqual(steps.map(\.delaySeconds), [600, 1200, 1800])
    }

    func testCadenceIsClampedToAtLeastOneMinute() {
        let steps = CriticalAlarmPlanner.schedule(from: prefs(minutes: 0, repeats: 2))
        XCTAssertEqual(steps.map(\.delaySeconds), [60, 120])
    }

    func testRepeatCountIsCappedAtTheAbsoluteMaximum() {
        let steps = CriticalAlarmPlanner.schedule(from: prefs(repeats: 999))
        XCTAssertEqual(steps.count, CriticalAlarmPlanner.absoluteMaxRepeats)
    }

    func testNonPositiveRepeatCountPlansNothing() {
        XCTAssertTrue(CriticalAlarmPlanner.schedule(from: prefs(repeats: 0)).isEmpty)
        XCTAssertTrue(CriticalAlarmPlanner.schedule(from: prefs(repeats: -3)).isEmpty)
    }

    // MARK: Remaining schedule (restore after a wholesale cancellation)

    func testRemainingScheduleKeepsOnlyFutureRepeats() {
        let anchor = CriticalAlarmAnchor(firedAt: now, repeatMinutes: 5, maxRepeats: 6)
        let remaining = CriticalAlarmPlanner.remainingSchedule(anchor: anchor, now: now.addingTimeInterval(600))
        XCTAssertEqual(remaining.map(\.index), [3, 4, 5, 6])
        XCTAssertEqual(remaining.map(\.delaySeconds), [300, 600, 900, 1200])
    }

    func testRemainingScheduleBeforeTheFirstRepeatIsTheFullRun() {
        let anchor = CriticalAlarmAnchor(firedAt: now, repeatMinutes: 3, maxRepeats: 3)
        let remaining = CriticalAlarmPlanner.remainingSchedule(anchor: anchor, now: now)
        XCTAssertEqual(remaining.map(\.delaySeconds), [180, 360, 540])
    }

    func testRemainingScheduleIsEmptyOnceTheRunIsOver() {
        let anchor = CriticalAlarmAnchor(firedAt: now, repeatMinutes: 5, maxRepeats: 6)
        let after = now.addingTimeInterval(2 * 3600)
        XCTAssertTrue(CriticalAlarmPlanner.remainingSchedule(anchor: anchor, now: after).isEmpty)
    }

    // MARK: Identifiers

    func testRepeatIdentifierRoundTrip() {
        let id = CriticalAlarmPlanner.identifier(forRepeat: 4)
        XCTAssertEqual(id, "critical-repeat-4")
        XCTAssertEqual(CriticalAlarmPlanner.repeatIndex(from: id), 4)
        XCTAssertTrue(CriticalAlarmPlanner.isRepeatIdentifier(id))
    }

    func testForeignIdentifiersAreNotRepeats() {
        XCTAssertNil(CriticalAlarmPlanner.repeatIndex(from: "contextual-readingGap"))
        XCTAssertNil(CriticalAlarmPlanner.repeatIndex(from: "glucose-alert-urgentLow"))
        XCTAssertNil(CriticalAlarmPlanner.repeatIndex(from: "critical-repeat-"))
        XCTAssertNil(CriticalAlarmPlanner.repeatIndex(from: "critical-repeat-x"))
        XCTAssertNil(CriticalAlarmPlanner.repeatIndex(from: "critical-repeat-0"))
    }

    func testAllRepeatIdentifiersCoverTheCap() {
        let all = CriticalAlarmPlanner.allRepeatIdentifiers
        XCTAssertEqual(all.count, CriticalAlarmPlanner.absoluteMaxRepeats)
        XCTAssertTrue(all.allSatisfy(CriticalAlarmPlanner.isRepeatIdentifier))
        // Every plannable step must be cancellable through this list.
        let planned = CriticalAlarmPlanner.schedule(from: prefs(repeats: Int.max))
        XCTAssertTrue(planned.allSatisfy { step in
            all.contains(CriticalAlarmPlanner.identifier(forRepeat: step.index))
        })
    }

    // MARK: Acknowledgment

    func testDefaultTapAcknowledgesUrgentLowAndItsRepeats() {
        XCTAssertTrue(CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: "glucose-alert-urgentLow"))
        XCTAssertTrue(CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: "critical-repeat-2"))
        XCTAssertFalse(CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: "glucose-alert-low"))
        XCTAssertFalse(CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: "glucose-predictive-low"))
        XCTAssertFalse(CriticalAlarmPlanner.acknowledgeCancelsRepeats(notificationIdentifier: "journal-540"))
    }

    func testUrgentLowIdentifierMatchesTheAlertServiceConvention() {
        // GlucoseAlertService names its requests "glucose-alert-<level rawValue>".
        XCTAssertEqual(CriticalAlarmPlanner.urgentLowAlertIdentifier,
                       "glucose-alert-\(GlucoseAlertLevel.urgentLow.rawValue)")
    }

    // MARK: Copy

    func testRepeatContentMentionsProgressAndCarriesNoGlucoseValue() {
        let copy = CriticalAlarmPlanner.repeatContent(index: 2, total: 6)
        XCTAssertFalse(copy.title.isEmpty)
        XCTAssertTrue(copy.body.contains("2 of 6"))
    }
}
