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
        id: UUID = UUID()
    ) -> InsulinDose {
        InsulinDose(id: id, units: units, timestamp: date(day, hour, minute),
                    insulinType: type, doseContext: context)
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

    func testSlotWindowIsPlusMinusSeventyFiveMinutes() {
        // 06:10 is 80 min before the 07:30 anchor — outside the window; the day
        // still gets a (slot-empty) row because it has data.
        let outside = rows(readings: [reading(1, 6, 10)])
        XCTAssertEqual(outside.count, 1)
        XCTAssertNil(outside[0].beforeBreakfast.mgdL)

        // 06:20 is 70 min before — inside.
        let inside = rows(readings: [reading(1, 6, 20, 95)])
        XCTAssertEqual(inside[0].beforeBreakfast.mgdL, 95)
    }

    func testAfterSlotTargetsAnchorPlusTwoHours() {
        // Breakfast 07:30 → "2h after breakfast" targets 09:30.
        let result = rows(readings: [reading(1, 9, 30, 160)])
        XCTAssertEqual(result[0].afterBreakfast.mgdL, 160)
        XCTAssertNil(result[0].beforeBreakfast.mgdL)
        XCTAssertEqual(result[0].afterBreakfast.slotDate, date(1, 9, 30))
    }

    func testFingerstickPreferredOverCloserCGM() {
        let cgm = reading(1, 7, 30, 140, type: .cgm)
        let stick = reading(1, 8, 30, 118, type: .fingerstick)   // 60 min away, still in window
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
        // 14:00 is inside both "before lunch" (13:00) and "2h after lunch"
        // (15:00) windows; the earlier slot claims it, the later stays empty.
        let result = rows(readings: [reading(1, 14, 0, 130)])
        XCTAssertEqual(result[0].beforeLunch.mgdL, 130)
        XCTAssertNil(result[0].afterLunch.mgdL)
    }

    func testInactiveReadingsAreIgnored() {
        let inactive = reading(1, 7, 30)
        inactive.isActive = false
        XCTAssertTrue(rows(readings: [inactive]).isEmpty)
    }

    // MARK: Meal anchors

    func testCarbEntryReanchorsTheMeal() {
        // Breakfast carb at 06:30 (inside ±120 min of 07:30) moves the anchor:
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
        let meal = dose(1, 7, 0, units: 4)                          // 30 min before anchor
        let correction = dose(1, 8, 50, units: 2, context: .correction) // 80 min after anchor
        let tooLate = dose(1, 10, 0, units: 6)                      // 150 min → dropped
        let result = rows(insulin: [meal, correction, tooLate])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].breakfastUnits, 6)
        XCTAssertEqual(Set(result[0].breakfastDoseIDs), Set([meal.id, correction.id]))
        XCTAssertNil(result[0].lunchUnits)
        XCTAssertNil(result[0].dinnerUnits)
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
