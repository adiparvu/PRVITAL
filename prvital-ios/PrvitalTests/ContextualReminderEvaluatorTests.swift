import XCTest
@testable import Prvital

final class ContextualReminderEvaluatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// All features on, with the default thresholds, so individual tests only
    /// tweak what they exercise.
    private func enabled() -> ContextualReminderSettings {
        var s = ContextualReminderSettings()
        s.readingGapEnabled = true
        s.mealContextEnabled = true
        return s
    }

    private func reminder(_ kind: ContextualReminderKind, in reminders: [ContextualReminder]) -> ContextualReminder? {
        reminders.first { $0.kind == kind }
    }

    // MARK: Master gating

    func testDisabledSettingsProduceNothing() {
        let input = ContextualReminderInput(
            lastReadingAt: now.addingTimeInterval(-6 * 3600),
            lastMealAt: now.addingTimeInterval(-5 * 60),
            lastMealCarbs: 80,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: .disabled, now: now)
        XCTAssertTrue(out.isEmpty)
    }

    func testFeatureSwitchesAreIndependent() {
        var settings = enabled()
        settings.mealContextEnabled = false
        let input = ContextualReminderInput(
            lastReadingAt: now.addingTimeInterval(-30 * 60),
            lastMealAt: now.addingTimeInterval(-5 * 60),
            lastMealCarbs: 80,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: settings, now: now)
        XCTAssertNotNil(reminder(.noRecentReading, in: out))
        XCTAssertNil(reminder(.carbsWithoutBolus, in: out))
        XCTAssertNil(reminder(.largeMealRecheck, in: out))
    }

    // MARK: Reading gap

    func testReadingGapScheduledFromLastReading() {
        // Last reading 30 min ago, gap 4h -> fire in 4h - 30m = 3h30m.
        let input = ContextualReminderInput(lastReadingAt: now.addingTimeInterval(-30 * 60))
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        let r = reminder(.noRecentReading, in: out)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fireDelay, 4 * 3600 - 30 * 60, accuracy: 1)
        XCTAssertEqual(r!.id, "noRecentReading")
    }

    func testReadingGapOverdueFiresAtMinLead() {
        // Last reading 10h ago -> gap already elapsed, clamp to minLead.
        let input = ContextualReminderInput(lastReadingAt: now.addingTimeInterval(-10 * 3600))
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        let r = reminder(.noRecentReading, in: out)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fireDelay, ContextualReminderSettings().minLeadSeconds, accuracy: 0.001)
    }

    func testReadingGapNeedsABaseline() {
        let out = ContextualReminderEvaluator.evaluate(
            input: .empty, settings: enabled(), now: now)
        XCTAssertNil(reminder(.noRecentReading, in: out))
    }

    // MARK: Carbs without bolus

    func testCarbsWithoutBolusFires() {
        // 40 g meal 5 min ago, no dose -> fire at meal + 15m grace = in 10m.
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-5 * 60),
            lastMealCarbs: 40,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        let r = reminder(.carbsWithoutBolus, in: out)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fireDelay, 10 * 60, accuracy: 1)
        XCTAssertTrue(r!.body.contains("40"))
    }

    func testBolusAtOrAfterMealSuppresses() {
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-10 * 60),
            lastMealCarbs: 40,
            lastInsulinAt: now.addingTimeInterval(-8 * 60))   // dose after the meal
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNil(reminder(.carbsWithoutBolus, in: out))
    }

    func testBolusBeforeMealDoesNotSuppress() {
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-10 * 60),
            lastMealCarbs: 40,
            lastInsulinAt: now.addingTimeInterval(-30 * 60))  // dose before the meal
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNotNil(reminder(.carbsWithoutBolus, in: out))
    }

    func testSmallCarbsBelowThresholdIgnored() {
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-5 * 60),
            lastMealCarbs: 8,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNil(reminder(.carbsWithoutBolus, in: out))
    }

    func testOldMealOutsideWindowIgnored() {
        // 40 g meal 2h ago, window is 90 min -> no longer actionable.
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-2 * 3600),
            lastMealCarbs: 40,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNil(reminder(.carbsWithoutBolus, in: out))
    }

    // MARK: Large-meal recheck

    func testLargeMealRecheckScheduled() {
        // 80 g meal 10 min ago, no reading after -> recheck at meal + 2h.
        let input = ContextualReminderInput(
            lastReadingAt: now.addingTimeInterval(-40 * 60),   // before the meal
            lastMealAt: now.addingTimeInterval(-10 * 60),
            lastMealCarbs: 80,
            lastInsulinAt: now.addingTimeInterval(-9 * 60))
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        let r = reminder(.largeMealRecheck, in: out)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fireDelay, 2 * 3600 - 10 * 60, accuracy: 1)
    }

    func testReadingAfterMealSuppressesRecheck() {
        let input = ContextualReminderInput(
            lastReadingAt: now.addingTimeInterval(-5 * 60),    // after the meal
            lastMealAt: now.addingTimeInterval(-10 * 60),
            lastMealCarbs: 80,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNil(reminder(.largeMealRecheck, in: out))
    }

    func testModerateMealBelowLargeThresholdNoRecheck() {
        // 40 g >= carb-bolus threshold but < large-meal threshold: a bolus nudge
        // may apply, but never a recheck.
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-5 * 60),
            lastMealCarbs: 40,
            lastInsulinAt: now.addingTimeInterval(-4 * 60))    // bolus logged, no nudge
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNil(reminder(.largeMealRecheck, in: out))
        XCTAssertNil(reminder(.carbsWithoutBolus, in: out))
    }

    func testStaleLargeMealBeyondMaxAgeIgnored() {
        // 80 g meal 7h ago, max age 6h -> too old to resurface.
        let input = ContextualReminderInput(
            lastMealAt: now.addingTimeInterval(-7 * 3600),
            lastMealCarbs: 80,
            lastInsulinAt: nil)
        var settings = enabled()
        settings.carbBolusWindowMinutes = 90        // keep carb nudge out of the way
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: settings, now: now)
        XCTAssertNil(reminder(.largeMealRecheck, in: out))
    }

    // MARK: Combined

    func testLargeUnbolusedMealYieldsBothMealReminders() {
        let input = ContextualReminderInput(
            lastReadingAt: now.addingTimeInterval(-90 * 60),
            lastMealAt: now.addingTimeInterval(-2 * 60),
            lastMealCarbs: 90,
            lastInsulinAt: nil)
        let out = ContextualReminderEvaluator.evaluate(input: input, settings: enabled(), now: now)
        XCTAssertNotNil(reminder(.carbsWithoutBolus, in: out))
        XCTAssertNotNil(reminder(.largeMealRecheck, in: out))
        // Stable, unique identifiers so the scheduler never stacks them.
        XCTAssertEqual(Set(out.map(\.id)).count, out.count)
    }
}
