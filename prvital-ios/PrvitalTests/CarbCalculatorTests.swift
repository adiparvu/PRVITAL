import XCTest
@testable import Prvital

final class CarbCalculatorTests: XCTestCase {

    func testCarbsForPortion() {
        // 200 g of a food with 12 g carbs / 100 g -> 24 g.
        XCTAssertEqual(CarbCalculator.carbs(per100g: 12, portionGrams: 200), 24, accuracy: 1e-6)
    }

    func testCarbsHalfPortion() {
        XCTAssertEqual(CarbCalculator.carbs(per100g: 50, portionGrams: 50), 25, accuracy: 1e-6)
    }

    func testZeroAndNegativeAreSafe() {
        XCTAssertEqual(CarbCalculator.carbs(per100g: 0, portionGrams: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(CarbCalculator.carbs(per100g: 12, portionGrams: -5), 0, accuracy: 1e-9)
        XCTAssertEqual(CarbCalculator.carbs(per100g: -3, portionGrams: 100), 0, accuracy: 1e-9)
    }

    func testNetCarbsSubtractsFiber() {
        XCTAssertEqual(CarbCalculator.netCarbs(total: 30, fiber: 8), 22, accuracy: 1e-6)
    }

    func testNetCarbsNeverNegative() {
        XCTAssertEqual(CarbCalculator.netCarbs(total: 5, fiber: 12), 0, accuracy: 1e-9)
    }

    func testCarbsWithNetOption() {
        // 100 g with 20 g carbs and 5 g fibre / 100 g -> net 15 g.
        let net = CarbCalculator.carbs(portionGrams: 100, carbsPer100g: 20, fiberPer100g: 5, useNetCarbs: true)
        XCTAssertEqual(net, 15, accuracy: 1e-6)
    }

    func testTotalCarbsIgnoresFiberWhenNetOff() {
        let total = CarbCalculator.carbs(portionGrams: 100, carbsPer100g: 20, fiberPer100g: 5, useNetCarbs: false)
        XCTAssertEqual(total, 20, accuracy: 1e-6)
    }

    func testNetCarbsIgnoredWhenFiberMissing() {
        let total = CarbCalculator.carbs(portionGrams: 100, carbsPer100g: 20, fiberPer100g: nil, useNetCarbs: true)
        XCTAssertEqual(total, 20, accuracy: 1e-6)
    }

    func testPortionForTargetCarbs() {
        // Want 30 g carbs from a food with 60 g / 100 g -> 50 g portion.
        XCTAssertEqual(CarbCalculator.portionGrams(forTargetCarbs: 30, carbsPer100g: 60), 50, accuracy: 1e-6)
    }

    func testPortionForTargetIsSafe() {
        XCTAssertEqual(CarbCalculator.portionGrams(forTargetCarbs: 30, carbsPer100g: 0), 0, accuracy: 1e-9)
    }
}
