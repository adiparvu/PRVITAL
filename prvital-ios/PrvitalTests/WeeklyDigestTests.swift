import XCTest
@testable import Prvital

final class WeeklyDigestTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A date in March 2026. Mar 2, 9 and 16 are Mondays; Mar 15 is a Sunday;
    /// Mar 18 is a Wednesday.
    private func date(_ day: Int, hour: Int = 12) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = hour
        return cal.date(from: dc)!
    }

    /// Six readings on March `day`: `inRange` of them at 100 mg/dL, the rest at
    /// 250 (high). Six clears `DailyBreakdown`'s per-day minimum.
    private func day(_ d: Int, inRange: Int) -> [GlucoseReading] {
        (0..<6).map { hour in
            GlucoseReading(valueMgdL: hour < inRange ? 100 : 250,
                           timestamp: date(d, hour: hour), source: .manual)
        }
    }

    private func compose(_ readings: [GlucoseReading],
                         reference: Date? = nil) -> WeeklyDigestSummary? {
        WeeklyDigest.compose(
            readings: readings,
            thresholds: .standard,
            referenceDate: reference ?? date(18),   // Wednesday mid-week
            calendar: cal
        )
    }

    // MARK: Week bucketing (Mon–Sun)

    func testLastFullWeekFromMidWeekReference() {
        let week = WeeklyDigest.lastFullWeek(before: date(18), calendar: cal)  // Wed Mar 18
        XCTAssertEqual(week.start, cal.startOfDay(for: date(9)))   // Mon Mar 9
        XCTAssertEqual(week.end, cal.startOfDay(for: date(16)))    // Mon Mar 16 (exclusive)
        XCTAssertEqual(week.duration, 7 * 86_400, accuracy: 1)
    }

    func testLastFullWeekFromMondayReference() {
        // On a Monday the week that just ended is the digest week.
        let week = WeeklyDigest.lastFullWeek(before: date(16, hour: 0), calendar: cal)
        XCTAssertEqual(week.start, cal.startOfDay(for: date(9)))
    }

    func testLastFullWeekFromSundayReferenceExcludesInProgressWeek() {
        // A Sunday still belongs to an in-progress week, so the digest covers
        // the Mon–Sun block before it.
        let week = WeeklyDigest.lastFullWeek(before: date(15), calendar: cal)  // Sun Mar 15
        XCTAssertEqual(week.start, cal.startOfDay(for: date(2)))   // Mon Mar 2
        XCTAssertEqual(week.end, cal.startOfDay(for: date(9)))
    }

    func testComposeCountsOnlyDigestWeekReadings() {
        // 3 days inside the digest week, plus noise in the current week and in
        // the week before the comparison week.
        let readings = day(9, inRange: 6) + day(10, inRange: 6) + day(11, inRange: 6)
            + day(17, inRange: 6)                       // current (in-progress) week
            + [GlucoseReading(valueMgdL: 250, timestamp: cal.date(from: DateComponents(year: 2026, month: 2, day: 25, hour: 8))!, source: .manual)]
        let summary = compose(readings)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.weekStart, cal.startOfDay(for: date(9)))
        XCTAssertEqual(summary?.readingCount, 18)
        XCTAssertEqual(summary?.timeInRange ?? 0, 1, accuracy: 1e-9)
        XCTAssertNil(summary?.timeInRangeDelta)   // comparison week has no data
    }

    // MARK: Delta math

    func testDeltaAgainstPreviousWeek() {
        // Digest week (Mar 9–): 18 of 24 in range = 0.75.
        // Previous week (Mar 2–): 9 of 18 in range = 0.50.
        let readings = day(9, inRange: 6) + day(10, inRange: 6) + day(11, inRange: 6) + day(12, inRange: 0)
            + day(2, inRange: 6) + day(3, inRange: 3) + day(4, inRange: 0)
        let summary = compose(readings)
        XCTAssertEqual(summary?.timeInRange ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertEqual(summary?.timeInRangeDelta ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertEqual(summary?.headline, "Time in range up 25 points")
    }

    // MARK: Headline rules

    func testHeadlineDownWhenPreviousWeekWasBetter() {
        // Digest 0.50 vs previous 0.75 → down 25 points.
        let readings = day(9, inRange: 6) + day(10, inRange: 3) + day(11, inRange: 0)
            + day(2, inRange: 6) + day(3, inRange: 6) + day(4, inRange: 6) + day(5, inRange: 0)
        let summary = compose(readings)
        XCTAssertEqual(summary?.timeInRangeDelta ?? 0, -0.25, accuracy: 1e-9)
        XCTAssertEqual(summary?.headline, "A tougher week — TIR down 25 points")
    }

    func testHeadlineSteadyOnSmallDelta() {
        // Both weeks 17 of 24 in range (≈70.8% → 71%); delta 0 < 3 points.
        let current = day(9, inRange: 6) + day(10, inRange: 6) + day(11, inRange: 5) + day(12, inRange: 0)
        let previous = day(2, inRange: 6) + day(3, inRange: 6) + day(4, inRange: 5) + day(5, inRange: 0)
        let summary = compose(current + previous)
        XCTAssertEqual(summary?.headline, "Steady week: 71% in range")
    }

    func testHeadlineSteadyWithoutPreviousWeek() {
        let summary = compose(day(9, inRange: 6) + day(10, inRange: 6) + day(11, inRange: 6))
        XCTAssertNil(summary?.timeInRangeDelta)
        XCTAssertEqual(summary?.headline, "Steady week: 100% in range")
    }

    func testHeadlineRuleSelectionDirectly() {
        XCTAssertEqual(WeeklyDigest.headline(timeInRange: 0.70, delta: 0.06), "Time in range up 6 points")
        XCTAssertEqual(WeeklyDigest.headline(timeInRange: 0.70, delta: -0.04), "A tougher week — TIR down 4 points")
        XCTAssertEqual(WeeklyDigest.headline(timeInRange: 0.70, delta: 0.02), "Steady week: 70% in range")
        XCTAssertEqual(WeeklyDigest.headline(timeInRange: 0.71, delta: nil), "Steady week: 71% in range")
    }

    // MARK: Sparse data

    func testNilWhenFewerThanThreeDaysWithData() {
        XCTAssertNil(compose(day(9, inRange: 6) + day(10, inRange: 6)))
        XCTAssertNil(compose([]))
    }

    func testNilWhenAllDataIsOutsideTheDigestWeek() {
        // Plenty of data, but all of it in the current (in-progress) week.
        XCTAssertNil(compose(day(16, inRange: 6) + day(17, inRange: 6) + day(18, inRange: 6)))
    }

    // MARK: Best / toughest day & streak

    func testBestToughestDayAndStreak() {
        // Mon Mar 9 at 50% TIR, Tue–Sun at 100%.
        var readings = day(9, inRange: 3)
        for d in 10...15 { readings += day(d, inRange: 6) }
        let summary = compose(readings)
        XCTAssertEqual(summary?.bestDay?.timeInRange ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(summary?.toughestDay?.timeInRange ?? 1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary?.toughestDay?.day, cal.startOfDay(for: date(9)))
        // Streak (70% target) counts back from Sunday: Tue–Sun met, Monday broke it.
        XCTAssertEqual(summary?.streakDays, 6)
    }
}
