import XCTest
@testable import Prvital

final class MealTimeClassifierTests: XCTestCase {

    func testMorningIsBreakfast() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 5), .breakfast)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 7), .breakfast)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 9), .breakfast)
    }

    func testLateMorningIsSnack() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 10), .morningSnack)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 11), .morningSnack)
    }

    func testMiddayIsLunch() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 12), .lunch)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 14), .lunch)
    }

    func testAfternoonIsEveningSnack() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 15), .eveningSnack)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 17), .eveningSnack)
    }

    func testEveningIsDinner() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 18), .dinner)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 21), .dinner)
    }

    func testLateNightAndEarlyMorningAreSnack() {
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 22), .eveningSnack)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 23), .eveningSnack)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 0), .eveningSnack)
        XCTAssertEqual(MealTimeClassifier.mealType(forHour: 4), .eveningSnack)
    }

    func testEveryHourMapsToSomeMeal() {
        // No hour should trap or fall outside the enum.
        for hour in 0..<24 {
            _ = MealTimeClassifier.mealType(forHour: hour)
        }
    }

    func testDateOverloadUsesHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2026, month: 7, day: 20, hour: 13, minute: 0)
        let noonish = cal.date(from: comps)!
        XCTAssertEqual(MealTimeClassifier.mealType(for: noonish, calendar: cal), .lunch)
    }
}
