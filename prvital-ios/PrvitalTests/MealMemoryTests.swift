import XCTest
@testable import Prvital

final class MealMemoryTests: XCTestCase {

    private let now = Date()

    func testRecallsTheLastMatchingMeal() {
        let mealAt = now.addingTimeInterval(-24 * 3600)
        let readings: [(Date, Double)] = stride(from: -30, through: 180, by: 5).map { minutes in
            (mealAt.addingTimeInterval(Double(minutes) * 60),
             minutes <= 0 ? 110 : 110 + min(90, Double(minutes)))
        }
        let recall = MealMemory.recall(
            query: "Paste carbonara",
            meals: [(mealAt, 45, "paste")],
            readings: readings,
            doses: [(mealAt.addingTimeInterval(-10 * 60), 4)],
            now: now)
        XCTAssertNotNil(recall)
        XCTAssertEqual(recall?.baselineMgdL, 110)
        XCTAssertEqual(recall?.peakMgdL, 200)
        XCTAssertEqual(recall?.dosedUnits, 4)
    }

    func testTooRecentMealIsSkipped() {
        let mealAt = now.addingTimeInterval(-30 * 60)
        let recall = MealMemory.recall(
            query: "paste", meals: [(mealAt, 45, "paste")],
            readings: [(mealAt, 110)], doses: [], now: now)
        XCTAssertNil(recall)
    }

    func testShortQueryNeverMatches() {
        let recall = MealMemory.recall(
            query: "pa", meals: [(now.addingTimeInterval(-86_400), 45, "paste")],
            readings: [], doses: [], now: now)
        XCTAssertNil(recall)
    }

    func testInsufficientCoverageIsSkipped() {
        let mealAt = now.addingTimeInterval(-24 * 3600)
        let recall = MealMemory.recall(
            query: "paste", meals: [(mealAt, 45, "paste")],
            readings: [(mealAt.addingTimeInterval(-5 * 60), 110)], doses: [], now: now)
        XCTAssertNil(recall)
    }
}
