import XCTest
@testable import Prvital

final class JournalDayCardTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 7; dc.day = day; dc.hour = hour; dc.minute = minute
        return cal.date(from: dc)!
    }

    private func reading(day: Int, hour: Int, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: date(day: day, hour: hour), source: .manual)
    }

    // MARK: - JournalDayStats

    func testStatsGlucoseEnvelope() {
        let readings = [
            reading(day: 20, hour: 6, 80),    // lowest
            reading(day: 20, hour: 12, 120),
            reading(day: 20, hour: 18, 220),  // highest, above range
            reading(day: 20, hour: 21, 100),
        ]
        let stats = JournalDayStats.build(
            readings: readings, insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard
        )
        XCTAssertEqual(stats.readingCount, 4)
        XCTAssertEqual(stats.lowestMgdL, 80, accuracy: 1e-9)
        XCTAssertEqual(stats.lowestAt, date(day: 20, hour: 6))
        XCTAssertEqual(stats.highestMgdL, 220, accuracy: 1e-9)
        XCTAssertEqual(stats.highestAt, date(day: 20, hour: 18))
        XCTAssertEqual(stats.averageMgdL, 130, accuracy: 1e-9)
        XCTAssertEqual(stats.timeInRange, 0.75, accuracy: 1e-9)   // 3 of 4 in 70–180
        XCTAssertEqual(stats.zone, .inRange)                       // zone of the average
        XCTAssertTrue(stats.hasGlucose)
    }

    func testStatsIgnoresInactiveReadings() {
        let losing = reading(day: 20, hour: 6, 40)
        losing.isActive = false
        let stats = JournalDayStats.build(
            readings: [losing, reading(day: 20, hour: 7, 100)],
            insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard
        )
        XCTAssertEqual(stats.readingCount, 1)
        XCTAssertEqual(stats.lowestMgdL, 100, accuracy: 1e-9)
        XCTAssertEqual(stats.timeInRange, 1, accuracy: 1e-9)
    }

    func testStatsTherapyTotals() {
        let insulin = [
            InsulinDose(units: 4, timestamp: date(day: 20, hour: 8)),
            InsulinDose(units: 12.5, timestamp: date(day: 20, hour: 22), insulinType: .longActing),
        ]
        let carbs = [
            CarbEntry(grams: 45, timestamp: date(day: 20, hour: 8)),
            CarbEntry(grams: 60, timestamp: date(day: 20, hour: 13)),
        ]
        let activity = [
            ActivityEntry(startTimestamp: date(day: 20, hour: 17), durationSeconds: 1800),
            ActivityEntry(startTimestamp: date(day: 20, hour: 19), durationSeconds: 600),
        ]
        let notes = [ObservationEntry(text: "Stressful day", timestamp: date(day: 20, hour: 21))]

        let stats = JournalDayStats.build(
            readings: [], insulin: insulin, carbs: carbs, activity: activity, observations: notes,
            thresholds: .standard
        )
        XCTAssertFalse(stats.hasGlucose)
        XCTAssertTrue(stats.hasTherapyData)
        XCTAssertEqual(stats.totalInsulinUnits, 16.5, accuracy: 1e-9)
        XCTAssertEqual(stats.doseCount, 2)
        XCTAssertEqual(stats.totalCarbGrams, 105, accuracy: 1e-9)
        XCTAssertEqual(stats.mealCount, 2)
        XCTAssertEqual(stats.activityMinutes, 40)
        XCTAssertEqual(stats.activityCount, 2)
        XCTAssertEqual(stats.noteCount, 1)
        XCTAssertEqual(stats.entryCount, 6)
    }

    func testStatsEmptyDay() {
        let stats = JournalDayStats.build(
            readings: [], insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard
        )
        XCTAssertFalse(stats.hasGlucose)
        XCTAssertFalse(stats.hasTherapyData)
        XCTAssertEqual(stats.entryCount, 0)
    }

    // MARK: - JournalDayBucket

    func testBucketsAreNewestFirstAndBucketedByDay() {
        let readings = [reading(day: 18, hour: 9, 110), reading(day: 20, hour: 9, 120)]
        let carbs = [CarbEntry(grams: 30, timestamp: date(day: 19, hour: 12))]
        let buckets = JournalDayBucket.build(
            glucose: readings, insulin: [], carbs: carbs, activity: [], observations: [],
            thresholds: .standard, calendar: cal
        )
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.map { cal.component(.day, from: $0.day) }, [20, 19, 18])
        XCTAssertEqual(buckets[0].readings.count, 1)
        XCTAssertEqual(buckets[1].stats.mealCount, 1)
        XCTAssertFalse(buckets[1].stats.hasGlucose)
        XCTAssertEqual(buckets[2].stats.readingCount, 1)
    }

    func testBucketsCapAtMaxDaysKeepingNewest() {
        let readings = (1...20).map { reading(day: $0, hour: 12, 100) }
        let buckets = JournalDayBucket.build(
            glucose: readings, insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard, calendar: cal, maxDays: 14
        )
        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(cal.component(.day, from: buckets.first!.day), 20)
        XCTAssertEqual(cal.component(.day, from: buckets.last!.day), 7)
    }

    func testBucketExcludesInactiveReadingsEverywhere() {
        let losing = reading(day: 20, hour: 6, 40)
        losing.isActive = false
        let buckets = JournalDayBucket.build(
            glucose: [losing, reading(day: 20, hour: 7, 100)],
            insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard, calendar: cal
        )
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].readings.count, 1)
        XCTAssertEqual(buckets[0].items.count, 1)
        XCTAssertEqual(buckets[0].stats.readingCount, 1)
    }

    func testBucketItemsAreNewestFirstAcrossKinds() {
        let buckets = JournalDayBucket.build(
            glucose: [reading(day: 20, hour: 8, 100)],
            insulin: [InsulinDose(units: 3, timestamp: date(day: 20, hour: 12))],
            carbs: [CarbEntry(grams: 20, timestamp: date(day: 20, hour: 10))],
            activity: [], observations: [],
            thresholds: .standard, calendar: cal
        )
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].items.map(\.kind), [.insulin, .carbs, .glucose])
    }

    func testBucketsEmptyInput() {
        let buckets = JournalDayBucket.build(
            glucose: [], insulin: [], carbs: [], activity: [], observations: [],
            thresholds: .standard, calendar: cal
        )
        XCTAssertTrue(buckets.isEmpty)
    }

    // MARK: - JournalCardDensity

    func testDensityRawValuesMatchPersistedStrings() {
        XCTAssertEqual(JournalCardDensity(rawValue: "compact"), .compact)
        XCTAssertEqual(JournalCardDensity(rawValue: "standard"), .standard)
        XCTAssertEqual(JournalCardDensity(rawValue: "detailed"), .detailed)
        XCTAssertNil(JournalCardDensity(rawValue: "bogus"))
        XCTAssertEqual(JournalCardDensity.allCases.count, 3)
    }

    func testDensityVisibilityFlags() {
        XCTAssertFalse(JournalCardDensity.compact.showsTherapyRow)
        XCTAssertFalse(JournalCardDensity.compact.showsEntryList)
        XCTAssertTrue(JournalCardDensity.standard.showsTherapyRow)
        XCTAssertFalse(JournalCardDensity.standard.showsEntryList)
        XCTAssertTrue(JournalCardDensity.detailed.showsTherapyRow)
        XCTAssertTrue(JournalCardDensity.detailed.showsEntryList)
    }
}
