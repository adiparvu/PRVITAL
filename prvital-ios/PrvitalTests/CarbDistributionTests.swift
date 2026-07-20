import XCTest
@testable import Prvital

final class CarbDistributionTests: XCTestCase {

    private func entry(_ grams: Double, _ type: MealType) -> CarbEntry {
        CarbEntry(grams: grams, timestamp: Date(timeIntervalSince1970: 1_700_000_000), mealType: type)
    }

    func testGroupsAndOrders() {
        // Provided out of canonical order.
        let entries = [
            entry(40, .dinner),
            entry(30, .breakfast),
            entry(20, .breakfast),
            entry(50, .lunch),
        ]
        let groups = CarbDistribution.byMealType(entries)
        // Canonical order: breakfast, lunch, dinner (no snacks present).
        XCTAssertEqual(groups.map(\.mealType), [.breakfast, .lunch, .dinner])
        XCTAssertEqual(groups[0].totalGrams, 50, accuracy: 1e-9) // 30 + 20
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].averageGrams, 25, accuracy: 1e-9)
        XCTAssertEqual(groups[1].totalGrams, 50, accuracy: 1e-9)
        XCTAssertEqual(groups[2].totalGrams, 40, accuracy: 1e-9)
    }

    func testZeroGramEntriesExcluded() {
        let groups = CarbDistribution.byMealType([entry(0, .lunch), entry(0, .dinner)])
        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(CarbDistribution.byMealType([]).isEmpty)
    }

    func testOnlyMealTypesWithEntriesAppear() {
        let groups = CarbDistribution.byMealType([entry(25, .eveningSnack)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].mealType, .eveningSnack)
    }
}
