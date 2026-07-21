import XCTest
@testable import Prvital

/// Tests for `InsightFeed` — the pure aggregator that turns the existing
/// analyzers into a ranked, capped `[InsightCard]`. All data is synthetic and a
/// fixed gregorian calendar is passed in so the day-period bucketing is stable.
final class InsightFeedTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Builders

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2024; c.month = 6; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    private func reading(_ mgdL: Double, day: Int, hour: Int, minute: Int = 0) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: date(day: day, hour: hour, minute: minute), source: .manual)
    }

    private func meal(_ grams: Double, type: MealType, day: Int, hour: Int) -> CarbEntry {
        CarbEntry(grams: grams, timestamp: date(day: day, hour: hour), mealType: type, source: .manual)
    }

    private func session(_ minutes: Int, day: Int, hour: Int, type: ActivityType = .walking) -> ActivityEntry {
        ActivityEntry(activityType: type, startTimestamp: date(day: day, hour: hour),
                      durationSeconds: minutes * 60, source: .manual)
    }

    private func card(id: String, severity: InsightSeverity, priority: Double, date: Date? = nil) -> InsightCard {
        InsightCard(id: id, title: id, detail: id, systemImage: "x",
                    severity: severity, tint: .neutral, date: date, priority: priority)
    }

    // MARK: - Empty state

    func testEmptyInputsProduceNoCards() {
        XCTAssertTrue(InsightFeed.build(readings: [], thresholds: .standard, calendar: calendar).isEmpty)
    }

    func testInRangeDataProducesNoCards() {
        let readings = (0..<12).map { reading(110, day: $0 % 5 + 1, hour: 10) }
        XCTAssertTrue(InsightFeed.build(readings: readings, thresholds: .standard, calendar: calendar).isEmpty)
    }

    // MARK: - Overnight lows → critical, ranked first

    func testOvernightLowsProduceCriticalCardRankedFirst() throws {
        let readings = (0..<12).map { reading(55, day: $0 % 5 + 1, hour: 2) }
        let cards = InsightFeed.build(readings: readings, thresholds: .standard, calendar: calendar)

        let first = try XCTUnwrap(cards.first)
        XCTAssertEqual(first.severity, .critical)
        XCTAssertEqual(first.tint, .critical)
        XCTAssertEqual(first.title, "Often low overnight")
        XCTAssertEqual(first.systemImage, "arrow.down.circle.fill")
        XCTAssertTrue(first.id.hasPrefix("pattern-overnight-frequentLow"))
    }

    // MARK: - Clinical ranking: lows outrank meal spikes

    func testLowsRankAboveMealSpikes() {
        var readings = (0..<12).map { reading(55, day: $0 % 5 + 1, hour: 2) }
        // Breakfast spikes: baseline ~100 before, peak ~190 after, on 3 days.
        for day in 1...3 {
            readings.append(reading(100, day: day, hour: 7, minute: 50))
            readings.append(reading(190, day: day, hour: 9))
        }
        let meals = (1...3).map { meal(45, type: .breakfast, day: $0, hour: 8) }

        let cards = InsightFeed.build(readings: readings, carbs: meals, thresholds: .standard, calendar: calendar)
        let lowIndex = cards.firstIndex { $0.id.hasPrefix("pattern-overnight-frequentLow") }
        let mealIndex = cards.firstIndex { $0.id == "meal-breakfast" }

        XCTAssertNotNil(lowIndex, "expected an overnight-low card")
        XCTAssertNotNil(mealIndex, "expected a breakfast meal-spike card")
        XCTAssertLessThan(lowIndex!, mealIndex!, "lows must rank above meal spikes")
    }

    // MARK: - Meal spike card content

    func testBreakfastSpikeCardContent() {
        var readings: [GlucoseReading] = []
        for day in 1...3 {
            readings.append(reading(100, day: day, hour: 7, minute: 50)) // baseline
            readings.append(reading(190, day: day, hour: 9))             // peak, +90, 60 min
        }
        let meals = (1...3).map { meal(45, type: .breakfast, day: $0, hour: 8) }

        let cards = InsightFeed.build(readings: readings, carbs: meals, thresholds: .standard, calendar: calendar)
        let mealCard = cards.first { $0.id == "meal-breakfast" }

        XCTAssertNotNil(mealCard)
        XCTAssertEqual(mealCard?.severity, .low)
        XCTAssertEqual(mealCard?.tint, .high)
        XCTAssertEqual(mealCard?.title, "Breakfast spikes +90 mg/dL")
        XCTAssertEqual(mealCard?.detail, "Peaks about 60 min after eating, over 3 meals")
    }

    func testSingleMealDoesNotSurface() {
        // Only one breakfast → below the min-meals bar → no meal card.
        let readings = [reading(100, day: 1, hour: 7, minute: 50), reading(190, day: 1, hour: 9)]
        let cards = InsightFeed.build(readings: readings, carbs: [meal(45, type: .breakfast, day: 1, hour: 8)],
                                      thresholds: .standard, calendar: calendar)
        XCTAssertNil(cards.first { $0.id == "meal-breakfast" })
    }

    // MARK: - Rebound highs

    func testTwoReboundsSurfaceAsHighSeverity() {
        let base = date(day: 1, hour: 10)
        func r(_ min: Double, _ v: Double) -> GlucoseReading {
            GlucoseReading(valueMgdL: v, timestamp: base.addingTimeInterval(min * 60), source: .manual)
        }
        let readings = [r(0, 120), r(10, 60), r(20, 100), r(30, 200),  // rebound 1
                        r(40, 120), r(50, 55), r(60, 100), r(70, 190)] // rebound 2
        let cards = InsightFeed.build(readings: readings, thresholds: .standard, calendar: calendar)
        let rebound = cards.first { $0.id == "rebound" }

        XCTAssertNotNil(rebound)
        XCTAssertEqual(rebound?.severity, .high)
        XCTAssertEqual(rebound?.tint, .warning)
    }

    func testSingleReboundDoesNotSurface() {
        let base = date(day: 1, hour: 10)
        func r(_ min: Double, _ v: Double) -> GlucoseReading {
            GlucoseReading(valueMgdL: v, timestamp: base.addingTimeInterval(min * 60), source: .manual)
        }
        let readings = [r(0, 120), r(10, 60), r(15, 65), r(20, 100), r(40, 200)] // one rebound only
        let cards = InsightFeed.build(readings: readings, thresholds: .standard, calendar: calendar)
        XCTAssertNil(cards.first { $0.id == "rebound" })
    }

    // MARK: - Activity impact

    func testActivityDropSurfacesAsInformationalPositive() {
        var readings: [GlucoseReading] = []
        for day in 1...2 {
            readings.append(reading(140, day: day, hour: 14, minute: 50)) // baseline
            readings.append(reading(100, day: day, hour: 15, minute: 20)) // nadir, -40
        }
        let sessions = (1...2).map { session(30, day: $0, hour: 15) }

        let cards = InsightFeed.build(readings: readings, activity: sessions,
                                      thresholds: .standard, calendar: calendar)
        let activity = cards.first { $0.id == "activity" }

        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.severity, .informational)
        XCTAssertEqual(activity?.tint, .positive)
        XCTAssertEqual(activity?.title, "Activity lowers your glucose")
    }

    // MARK: - Cap

    func testBuildCapsAtMaxCards() {
        var readings = (0..<12).map { reading(55, day: $0 % 5 + 1, hour: 2) }      // overnight lows
        readings += (0..<12).map { reading(220, day: $0 % 5 + 1, hour: 14) }        // afternoon highs
        readings += (0..<12).map { reading(220, day: $0 % 5 + 1, hour: 20) }        // evening highs
        for day in 1...3 {                                                          // breakfast spikes + dawn
            readings.append(reading(100, day: day, hour: 7, minute: 50))
            readings.append(reading(190, day: day, hour: 9))
        }
        for day in 1...2 {                                                          // activity drops
            readings.append(reading(140, day: day, hour: 15, minute: 50))
            readings.append(reading(100, day: day, hour: 16, minute: 20))
        }
        let meals = (1...3).map { meal(45, type: .breakfast, day: $0, hour: 8) }
        let sessions = (1...2).map { session(30, day: $0, hour: 16) }

        let cards = InsightFeed.build(readings: readings, carbs: meals, activity: sessions,
                                      thresholds: .standard, calendar: calendar)
        XCTAssertEqual(cards.count, InsightFeed.maxCards, "feed should be capped")
        // The top of a crowded feed must be the most severe findings, not meals/activity.
        XCTAssertTrue(cards.allSatisfy { $0.severity >= .moderate })
        XCTAssertEqual(cards.first?.severity, .critical)
    }

    // MARK: - Pure ranking (rank)

    func testRankOrdersBySeverityThenPriority() {
        let ranked = InsightFeed.rank([
            card(id: "info", severity: .informational, priority: 0.9),
            card(id: "critLow", severity: .critical, priority: 0.2),
            card(id: "moderate", severity: .moderate, priority: 0.5),
            card(id: "critHigh", severity: .critical, priority: 0.8),
        ])
        XCTAssertEqual(ranked.map(\.id), ["critHigh", "critLow", "moderate", "info"])
    }

    func testRankBreaksTiesByRecency() {
        let older = card(id: "old", severity: .high, priority: 0.5, date: Date(timeIntervalSince1970: 100))
        let newer = card(id: "new", severity: .high, priority: 0.5, date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(InsightFeed.rank([older, newer]).map(\.id), ["new", "old"])
    }

    func testRankIsDeterministicForFullTies() {
        let a = card(id: "aaa", severity: .moderate, priority: 0.5)
        let b = card(id: "bbb", severity: .moderate, priority: 0.5)
        XCTAssertEqual(InsightFeed.rank([b, a]).map(\.id), ["aaa", "bbb"])
    }

    func testRankCapsAtMaxCards() {
        let many = (0..<8).map { card(id: "\($0)", severity: .moderate, priority: Double(8 - $0) / 8) }
        XCTAssertEqual(InsightFeed.rank(many).count, InsightFeed.maxCards)
    }
}
