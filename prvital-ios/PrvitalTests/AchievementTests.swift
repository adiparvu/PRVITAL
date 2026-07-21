import XCTest
@testable import Prvital

final class AchievementTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(day: Int, hour: Int) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 6; dc.day = day; dc.hour = hour
        return cal.date(from: dc)!
    }

    // MARK: Evaluator

    func testProgressAndUnlock() {
        var i = AchievementInputs()
        i.totalReadings = 1
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.firstReading, i))

        i.loggedMeals = 25
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.meals25, i))
        XCTAssertFalse(AchievementEvaluator.isUnlocked(.meals100, i))
        let p = AchievementEvaluator.progress(.meals100, i)
        XCTAssertEqual(p.current, 25)
        XCTAssertEqual(p.target, 100)
    }

    func testStreakBadgesUseBestStreak() {
        var i = AchievementInputs()
        i.bestStreakDays = 14
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.streak7, i))
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.streak14, i))
        XCTAssertFalse(AchievementEvaluator.isUnlocked(.streak30, i))
    }

    func testGmiBadge() {
        var i = AchievementInputs()
        i.bestGmi = 7.4
        XCTAssertFalse(AchievementEvaluator.isUnlocked(.steadyGmi, i))
        i.bestGmi = 6.8
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.steadyGmi, i))
    }

    // MARK: Builder

    func testBuilderCountsMealsAndPerfectDay() {
        // Day 1: eight in-range readings → a perfect day.
        var readings: [GlucoseReading] = []
        for h in 8..<16 {
            readings.append(GlucoseReading(valueMgdL: 120, timestamp: date(day: 1, hour: h), source: .manual))
        }
        let meals = (0..<3).map { CarbEntry(grams: 40, timestamp: date(day: 1, hour: 8 + $0)) }

        let inputs = AchievementInputsBuilder.make(
            readings: readings, meals: meals, thresholds: .standard,
            goalFraction: 0.70, now: date(day: 1, hour: 20), calendar: cal)

        XCTAssertEqual(inputs.totalReadings, 8)
        XCTAssertEqual(inputs.loggedMeals, 3)
        XCTAssertEqual(inputs.daysWithData, 1)
        XCTAssertEqual(inputs.perfectDays, 1)
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.firstReading, inputs))
        XCTAssertTrue(AchievementEvaluator.isUnlocked(.perfectDay, inputs))
    }

    func testBuilderShortDaysDoNotCountAsPerfect() {
        // Only three readings in a day → below the per-day minimum.
        let readings = (0..<3).map { GlucoseReading(valueMgdL: 120, timestamp: date(day: 2, hour: 8 + $0), source: .manual) }
        let inputs = AchievementInputsBuilder.make(
            readings: readings, meals: [], thresholds: .standard,
            goalFraction: 0.70, now: date(day: 2, hour: 20), calendar: cal)
        XCTAssertEqual(inputs.daysWithData, 1)
        XCTAssertEqual(inputs.perfectDays, 0)
    }

    // MARK: Store (monotonic)

    @MainActor
    func testStoreIsMonotonic() {
        let suite = "test.achievements.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AchievementStore(defaults: defaults)

        let fresh1 = store.record(unlocked: [.firstReading, .firstMeal])
        XCTAssertEqual(Set(fresh1), [.firstReading, .firstMeal])
        XCTAssertEqual(store.earned, [.firstReading, .firstMeal])

        // Re-recording a subset earns nothing new and never removes earned ones.
        let fresh2 = store.record(unlocked: [.firstReading])
        XCTAssertTrue(fresh2.isEmpty)
        XCTAssertEqual(store.earned, [.firstReading, .firstMeal])

        XCTAssertEqual(store.unseenCount, 2)
        store.markAllSeen()
        XCTAssertEqual(store.unseenCount, 0)
    }
}
