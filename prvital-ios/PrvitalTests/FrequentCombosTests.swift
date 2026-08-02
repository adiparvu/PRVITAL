import XCTest
@testable import Prvital

final class FrequentCombosTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ d: Double, plusMinutes m: Double = 0) -> Date {
        now.addingTimeInterval(-d * 86_400 + m * 60)
    }

    func testRepeatMealWithUsualDose() {
        let meals = [
            (date: daysAgo(1), grams: 45.0, food: "Paste" as String?),
            (date: daysAgo(3), grams: 45.0, food: "Paste" as String?),
            (date: daysAgo(5), grams: 45.0, food: "paste" as String?),
        ]
        let doses = [
            (date: daysAgo(1, plusMinutes: -10), units: 4.0),
            (date: daysAgo(3, plusMinutes: 5), units: 4.5),
            (date: daysAgo(5, plusMinutes: -12), units: 4.0),
        ]
        let combos = FrequentCombos.detect(meals: meals, doses: doses)
        XCTAssertEqual(combos.count, 1)
        XCTAssertEqual(combos[0].grams, 45)
        XCTAssertEqual(combos[0].units, 4.0)   // median of 4, 4, 4.5
        XCTAssertEqual(combos[0].occurrences, 3)
    }

    func testOneOffMealIsNotAHabit() {
        let combos = FrequentCombos.detect(
            meals: [(date: daysAgo(2), grams: 60, food: "Pizza")], doses: [])
        XCTAssertTrue(combos.isEmpty)
    }

    func testUnbolusedMealHasNoDose() {
        let meals = [
            (date: daysAgo(1), grams: 20.0, food: "Măr" as String?),
            (date: daysAgo(2), grams: 20.0, food: "măr" as String?),
        ]
        let combos = FrequentCombos.detect(meals: meals, doses: [])
        XCTAssertEqual(combos.count, 1)
        XCTAssertNil(combos[0].units)
    }

    func testDoseOutsidePairingWindowDoesNotAttach() {
        let meals = [
            (date: daysAgo(1), grams: 30.0, food: "Iaurt" as String?),
            (date: daysAgo(2), grams: 30.0, food: "Iaurt" as String?),
        ]
        // A basal shot an hour away must not become "the usual dose".
        let doses = [(date: daysAgo(1, plusMinutes: -60), units: 18.0)]
        let combos = FrequentCombos.detect(meals: meals, doses: doses)
        XCTAssertEqual(combos.count, 1)
        XCTAssertNil(combos[0].units)
    }

    func testRankedByFrequencyThenRecency() {
        var meals: [(date: Date, grams: Double, food: String?)] = []
        for d in [1.0, 2, 4] { meals.append((daysAgo(d), 45, "Paste")) }
        for d in [1.5, 6] { meals.append((daysAgo(d), 30, "Pâine")) }
        let combos = FrequentCombos.detect(meals: meals, doses: [])
        XCTAssertEqual(combos.first?.foodDescription, "Paste")
        XCTAssertEqual(combos.count, 2)
    }
}
