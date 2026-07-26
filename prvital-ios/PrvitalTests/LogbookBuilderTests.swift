import XCTest
@testable import Prvital

final class LogbookBuilderTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    private func interval(_ days: ClosedRange<Int>) -> DateInterval {
        DateInterval(start: date(days.lowerBound, 0), end: date(days.upperBound, 23, 59))
    }

    private func reading(
        _ day: Int, _ hour: Int, _ minute: Int = 0,
        _ mgdL: Double = 110,
        type: GlucoseMeasurementType = .fingerstick,
        id: UUID = UUID()
    ) -> GlucoseReading {
        GlucoseReading(
            id: id, valueMgdL: mgdL, timestamp: date(day, hour, minute),
            source: type == .cgm ? .dexcom : .manual, measurementType: type
        )
    }

    private func dose(
        _ day: Int, _ hour: Int, _ minute: Int = 0,
        units: Double,
        type: InsulinType = .rapidActing,
        context: InsulinDoseContext = .mealBolus,
        tag: DoseMealTag? = nil,
        id: UUID = UUID()
    ) -> InsulinDose {
        InsulinDose(id: id, units: units, timestamp: date(day, hour, minute),
                    insulinType: type, doseContext: context, mealTag: tag)
    }

    private func rows(
        readings: [GlucoseReading] = [],
        insulin: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        observations: [ObservationEntry] = [],
        days: ClosedRange<Int> = 1...1,
        anchors: LogbookAnchors = .standard
    ) -> [LogbookRow] {
        LogbookBuilder.rows(
            readings: readings, insulin: insulin, carbs: carbs,
            observations: observations,
            interval: interval(days), calendar: cal, anchors: anchors
        )
    }

    // MARK: Slot bucketing

    func testClosestReadingToSlotTargetWins() {
        // Default breakfast anchor 07:30: 07:40 (10 min away) beats 07:00 (30 min).
        let far = reading(1, 7, 0, 100)
        let near = reading(1, 7, 40, 120)
        let result = rows(readings: [far, near])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 120)
        XCTAssertEqual(result[0].beforeBreakfast.readingID, near.id)
        XCTAssertNil(result[0].afterBreakfast.mgdL)
    }

    func testBeforeSlotLooksBackwardFromTheMeal() {
        // The "before" window reaches 90 min back from the 07:30 anchor…
        let inside = rows(readings: [reading(1, 6, 10, 95)])
        XCTAssertEqual(inside[0].beforeBreakfast.mgdL, 95)

        // …but only 10 min past it: a value from after eating can never be
        // "before" (07:45 is outside; the day still gets a row).
        let after = rows(readings: [reading(1, 7, 45)])
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(after[0].beforeBreakfast.mgdL)
    }

    func testAfterSlotWindowIsPlusMinusSeventyFiveMinutes() {
        // "2h after breakfast" targets 09:30: 10:50 (80 min) is outside,
        // 10:40 (70 min) is inside.
        let outside = rows(readings: [reading(1, 10, 50)])
        XCTAssertNil(outside[0].afterBreakfast.mgdL)

        let inside = rows(readings: [reading(1, 10, 40, 175)])
        XCTAssertEqual(inside[0].afterBreakfast.mgdL, 175)
    }

    func testAfterSlotTargetsAnchorPlusTwoHours() {
        // Breakfast 07:30 → "2h after breakfast" targets 09:30.
        let result = rows(readings: [reading(1, 9, 30, 160)])
        XCTAssertEqual(result[0].afterBreakfast.mgdL, 160)
        XCTAssertNil(result[0].beforeBreakfast.mgdL)
        XCTAssertEqual(result[0].afterBreakfast.slotDate, date(1, 9, 30))
    }

    func testFingerstickPreferredOverCloserCGM() {
        let cgm = reading(1, 7, 30, 140, type: .cgm)             // dead on the anchor
        let stick = reading(1, 6, 30, 118, type: .fingerstick)   // 60 min before, in window
        let result = rows(readings: [cgm, stick])
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 118)
        XCTAssertEqual(result[0].beforeBreakfast.readingID, stick.id)
    }

    func testCGMUsedAsFallbackWhenNoDiscreteReading() {
        let cgm = reading(1, 7, 35, 140, type: .cgm)
        let result = rows(readings: [cgm])
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 140)
        XCTAssertEqual(result[0].beforeBreakfast.readingID, cgm.id)
    }

    func testReadingFillsAtMostOneSlot() {
        // 21:30 is inside both "2h after dinner" (21:00 ±75) and "bedtime"
        // (22:30 ±75); the earlier slot claims it, the later stays empty.
        let result = rows(readings: [reading(1, 21, 30, 130)])
        XCTAssertEqual(result[0].afterDinner.mgdL, 130)
        XCTAssertNil(result[0].bedtime.mgdL)
    }

    func testInactiveReadingsAreIgnored() {
        let inactive = reading(1, 7, 30)
        inactive.isActive = false
        XCTAssertTrue(rows(readings: [inactive]).isEmpty)
    }

    // MARK: Meal anchors

    func testDeclaredMealAnchorsTheColumns() {
        // An entry DECLARED breakfast at 06:30 anchors the meal there:
        // "before" targets 06:30 and "2h after" targets 08:30.
        let carb = CarbEntry(grams: 40, timestamp: date(1, 6, 30), mealType: .breakfast)
        let before = reading(1, 6, 25, 96)
        let after = reading(1, 8, 30, 170)
        let result = rows(readings: [before, after], carbs: [carb])
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 96)
        XCTAssertEqual(result[0].beforeBreakfast.slotDate, date(1, 6, 30))
        XCTAssertEqual(result[0].afterBreakfast.mgdL, 170)
        XCTAssertEqual(result[0].afterBreakfast.slotDate, date(1, 8, 30))
    }

    func testDeclaredMealFarFromTimetableStillAnchorsExactly() {
        // A late lunch declared at 15:30 — far outside the old ±120 window —
        // now anchors the lunch columns at the real meal.
        let carb = CarbEntry(grams: 55, timestamp: date(1, 15, 30), mealType: .lunch)
        let before = reading(1, 15, 0, 104)
        let after = reading(1, 17, 30, 152)
        let result = rows(readings: [before, after], carbs: [carb])
        XCTAssertEqual(result[0].beforeLunch.mgdL, 104)
        XCTAssertEqual(result[0].beforeLunch.slotDate, date(1, 15, 30))
        XCTAssertEqual(result[0].afterLunch.mgdL, 152)
    }

    func testSnackNeverMovesAMealAnchor() {
        // A morning snack near breakfast time must not re-anchor breakfast:
        // the timetable (07:30) stays, so 07:00 still lands "before breakfast".
        let snack = CarbEntry(grams: 15, timestamp: date(1, 6, 30), mealType: .morningSnack)
        let before = reading(1, 7, 0, 101)
        let result = rows(readings: [before], carbs: [snack])
        XCTAssertEqual(result[0].beforeBreakfast.slotDate, date(1, 7, 30))
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 101)
    }

    func testFixedAnchorUsedWhenNoCarbEntry() {
        let result = rows(readings: [reading(1, 7, 30, 105)])
        XCTAssertEqual(result[0].beforeBreakfast.slotDate, date(1, 7, 30))
        XCTAssertEqual(result[0].bedtime.slotDate, date(1, 22, 30))
    }

    func testAnchorsDerivedFromGlucoseSchedule() {
        let anchors = LogbookAnchors(scheduleSlots: [
            GlucoseLogSlot(label: "Waking", minutesFromMidnight: 7 * 60),
            GlucoseLogSlot(label: "Before lunch", minutesFromMidnight: 12 * 60),
            GlucoseLogSlot(label: "Before dinner", minutesFromMidnight: 18 * 60, enabled: false),
            GlucoseLogSlot(label: "Bedtime", minutesFromMidnight: 23 * 60 + 15),
        ])
        XCTAssertEqual(anchors.breakfastMinutes, 7 * 60)
        XCTAssertEqual(anchors.lunchMinutes, 12 * 60)
        XCTAssertEqual(anchors.dinnerMinutes, 19 * 60)          // disabled slot → default
        XCTAssertEqual(anchors.bedtimeMinutes, 23 * 60 + 15)
    }

    func testBedtimeScheduleWrapsMidnight() {
        // 23:00 counts as earlier bedtime than 00:30 on the wrapped clock.
        let anchors = LogbookAnchors(scheduleSlots: [
            GlucoseLogSlot(label: "Night", minutesFromMidnight: 30),
            GlucoseLogSlot(label: "Bed", minutesFromMidnight: 23 * 60),
        ])
        XCTAssertEqual(anchors.bedtimeMinutes, 23 * 60)
    }

    // MARK: Insulin

    func testInsulinSumsBolusDosesWithinNinetyMinutes() {
        let meal = dose(1, 7, 0, units: 4)         // 30 min before anchor
        let second = dose(1, 8, 50, units: 2)      // 80 min after anchor
        let tooLate = dose(1, 10, 0, units: 6)     // 150 min → dropped
        let result = rows(insulin: [meal, second, tooLate])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].breakfastUnits, 6)
        XCTAssertEqual(Set(result[0].breakfastDoseIDs), Set([meal.id, second.id]))
        XCTAssertNil(result[0].lunchUnits)
        XCTAssertNil(result[0].dinnerUnits)
    }

    func testExplicitMealTagWinsOverTheClock() {
        // 12:40 is squarely "lunch" by the clock (13:00 anchor), but the user
        // said this dose was for breakfast — their word wins.
        let tagged = dose(1, 12, 40, units: 5, tag: .breakfast)
        let result = rows(insulin: [tagged])
        XCTAssertEqual(result[0].breakfastUnits, 5)
        XCTAssertEqual(result[0].breakfastDoseIDs, [tagged.id])
        XCTAssertNil(result[0].lunchUnits)
    }

    func testSnackTaggedDoseStaysOutOfMealColumns() {
        // A dose for a snack near lunchtime must not inflate "Insulin lunch".
        let snack = dose(1, 12, 50, units: 2, tag: .snack)
        let result = rows(insulin: [snack])
        XCTAssertEqual(result.count, 1)   // the day still gets a row
        XCTAssertNil(result[0].breakfastUnits)
        XCTAssertNil(result[0].lunchUnits)
        XCTAssertNil(result[0].dinnerUnits)
    }

    func testUntaggedCorrectionStaysOutOfMealColumns() {
        // An explicit correction is not "insulin for lunch", even at 13:10.
        let correction = dose(1, 13, 10, units: 2, context: .correction)
        let bolus = dose(1, 13, 0, units: 6)
        let result = rows(insulin: [correction, bolus])
        XCTAssertEqual(result[0].lunchUnits, 6)
        XCTAssertEqual(result[0].lunchDoseIDs, [bolus.id])
    }

    func testBasalDosesAreExcluded() {
        let basal = dose(1, 7, 30, units: 20, type: .longActing, context: .basal)
        let bolus = dose(1, 7, 15, units: 4)
        let result = rows(insulin: [basal, bolus])
        XCTAssertEqual(result[0].breakfastUnits, 4)
        XCTAssertEqual(result[0].breakfastDoseIDs, [bolus.id])

        // A basal-only day contributes nothing to the register.
        XCTAssertTrue(rows(insulin: [basal]).isEmpty)
    }

    func testSingleDoseKeepsItsIDForEditing() {
        let lunch = dose(1, 13, 10, units: 5)
        let result = rows(insulin: [lunch])
        XCTAssertEqual(result[0].lunchUnits, 5)
        XCTAssertEqual(result[0].lunchDoseIDs, [lunch.id])
        XCTAssertNil(result[0].breakfastUnits)
    }

    // MARK: Pinned readings

    func testPinnedReadingClaimsItsSlotWhateverTheClockSays() {
        // 12:20 would auto-fill "before lunch", but the user pinned it to
        // "2h after breakfast" (09:30 target, far outside the ±75 window).
        let pinned = reading(1, 12, 20, 150)
        pinned.logbookSlot = .afterBreakfast
        let result = rows(readings: [pinned])
        XCTAssertEqual(result[0].afterBreakfast.mgdL, 150)
        XCTAssertTrue(result[0].afterBreakfast.isPinned)
        XCTAssertNil(result[0].beforeLunch.mgdL)
    }

    func testPinnedReadingBeatsACloserAutomaticCandidate() {
        // The pin wins the column even when an unpinned reading sits right on
        // the slot's target; auto placement is only for what's left.
        let pinned = reading(1, 10, 0, 88)
        pinned.logbookSlot = .beforeBreakfast
        let auto = reading(1, 7, 20, 130)
        let result = rows(readings: [pinned, auto])
        XCTAssertEqual(result[0].beforeBreakfast.mgdL, 88)
        XCTAssertTrue(result[0].beforeBreakfast.isPinned)
        // 07:20 fits no other window (after-breakfast starts 08:15) → unused.
        XCTAssertNil(result[0].afterBreakfast.mgdL)
        XCTAssertFalse(result[0].beforeLunch.isPinned)
    }

    // MARK: Comments

    func testCommentJoinsObservationsAndLowMarker() {
        let note = ObservationEntry(tags: [], text: "Stress at work", timestamp: date(1, 10))
        let tagsOnly = ObservationEntry(tags: [.illness], text: nil, timestamp: date(1, 11))
        let low = reading(1, 2, 51, 47, type: .cgm)
        let result = rows(readings: [low], observations: [note, tagsOnly])
        XCTAssertEqual(result[0].comment, "Stress at work; Illness; Low 47 at 02:51")
    }

    func testConsecutiveLowsGroupIntoOneEpisodeAtTheNadir() {
        let lows = [
            reading(1, 2, 0, 55, type: .cgm),
            reading(1, 2, 10, 47, type: .cgm),
            reading(1, 2, 20, 52, type: .cgm),
            reading(1, 6, 0, 65, type: .cgm),   // > 30 min later → its own episode
        ]
        let result = rows(readings: lows)
        XCTAssertEqual(result[0].comment, "Low 47 at 02:10; Low 65 at 06:00")
    }

    // MARK: Ordering & emptiness

    func testRowsAreNewestFirstAndSkipEmptyDays() {
        let result = rows(
            readings: [reading(1, 7, 30), reading(3, 7, 30)],
            days: 1...3
        )
        XCTAssertEqual(result.count, 2)   // day 2 has no data → no row
        XCTAssertEqual(result[0].day, cal.startOfDay(for: date(3, 12)))
        XCTAssertEqual(result[1].day, cal.startOfDay(for: date(1, 12)))
    }

    func testEmptyInputsAndEmptyIntervalProduceNoRows() {
        XCTAssertTrue(rows().isEmpty)

        let zeroLength = DateInterval(start: date(1, 12), end: date(1, 12))
        let result = LogbookBuilder.rows(
            readings: [reading(1, 12)], insulin: [], carbs: [], observations: [],
            interval: zeroLength, calendar: cal
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRecordsOutsideTheIntervalAreExcluded() {
        let result = rows(readings: [reading(1, 7, 30), reading(5, 7, 30)], days: 1...2)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].day, cal.startOfDay(for: date(1, 12)))
    }
}
