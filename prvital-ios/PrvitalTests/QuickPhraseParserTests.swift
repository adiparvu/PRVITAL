import XCTest
@testable import Prvital

final class QuickPhraseParserTests: XCTestCase {

    func testRomanianMealAndBolus() {
        let p = QuickPhraseParser.parse("45g paste și 4 unități", unit: .mgdL)
        XCTAssertEqual(p.carbGrams, 45)
        XCTAssertEqual(p.insulinUnits, 4)
        XCTAssertEqual(p.foodDescription, "paste")
        XCTAssertNil(p.glucoseMgdL)
    }

    func testEnglishWithSeparatedUnits() {
        let p = QuickPhraseParser.parse("ate 60 g pizza and took 6 u", unit: .mgdL)
        XCTAssertEqual(p.carbGrams, 60)
        XCTAssertEqual(p.insulinUnits, 6)
        XCTAssertEqual(p.foodDescription, "pizza")
    }

    func testBareNumberIsGlucose() {
        let p = QuickPhraseParser.parse("125", unit: .mgdL)
        XCTAssertEqual(p.glucoseMgdL, 125)
    }

    func testGlucoseKeyword() {
        let p = QuickPhraseParser.parse("glicemie 98 și 30g pâine", unit: .mgdL)
        XCTAssertEqual(p.glucoseMgdL, 98)
        XCTAssertEqual(p.carbGrams, 30)
        XCTAssertEqual(p.foodDescription, "pâine")
    }

    func testDecimalCommaInsulin() {
        let p = QuickPhraseParser.parse("4,5 ui", unit: .mgdL)
        XCTAssertEqual(p.insulinUnits, 4.5)
    }

    func testMmolConversion() {
        let p = QuickPhraseParser.parse("6.2 mmol", unit: .mgdL)
        XCTAssertEqual(p.glucoseMgdL ?? 0, 6.2 * GlucoseUnit.conversionFactor, accuracy: 0.01)
    }

    func testMmolUserBareNumber() {
        let p = QuickPhraseParser.parse("6.2", unit: .mmolL)
        XCTAssertEqual(p.glucoseMgdL ?? 0, 6.2 * GlucoseUnit.conversionFactor, accuracy: 0.01)
    }

    func testCountedFoodIsNotGlucose() {
        // The 2 in "2 ouă" counts eggs; it must never become 36 mg/dL.
        let p = QuickPhraseParser.parse("2 ouă", unit: .mmolL)
        XCTAssertNil(p.glucoseMgdL)
        XCTAssertTrue(p.isEmpty)
    }

    func testGluedTokens() {
        let p = QuickPhraseParser.parse("45g 4u 120mg", unit: .mgdL)
        XCTAssertEqual(p.carbGrams, 45)
        XCTAssertEqual(p.insulinUnits, 4)
        XCTAssertEqual(p.glucoseMgdL, 120)
    }

    func testEmptyAndNoise() {
        XCTAssertTrue(QuickPhraseParser.parse("", unit: .mgdL).isEmpty)
        XCTAssertTrue(QuickPhraseParser.parse("am mâncat bine azi", unit: .mgdL).isEmpty)
    }
}
