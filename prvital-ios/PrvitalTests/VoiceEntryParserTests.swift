import XCTest
@testable import Prvital

final class VoiceEntryParserTests: XCTestCase {

    // MARK: Carbs

    func testRomanianCarbsWithFood() {
        let result = VoiceEntryParser.parse("60 de grame, pizza")
        XCTAssertEqual(result.carbsGrams, 60)
        XCTAssertEqual(result.foodDescription, "Pizza")
        XCTAssertNil(result.insulinUnits)
        XCTAssertNil(result.spokenGlucose)
    }

    func testEnglishCarbs() {
        let result = VoiceEntryParser.parse("45 grams of pasta")
        XCTAssertEqual(result.carbsGrams, 45)
        XCTAssertEqual(result.foodDescription, "Pasta")
    }

    func testMultiWordFoodKeepsCasing() {
        let result = VoiceEntryParser.parse("30 grame Pizza Margherita")
        XCTAssertEqual(result.carbsGrams, 30)
        XCTAssertEqual(result.foodDescription, "Pizza Margherita")
    }

    func testCarbSynonym() {
        XCTAssertEqual(VoiceEntryParser.parse("40 de glucide").carbsGrams, 40)
        XCTAssertEqual(VoiceEntryParser.parse("25 carbs").carbsGrams, 25)
    }

    // MARK: Insulin

    func testRomanianInsulinWithDiacritics() {
        XCTAssertEqual(VoiceEntryParser.parse("6 unități").insulinUnits, 6)
    }

    func testRomanianInsulinWithoutDiacritics() {
        XCTAssertEqual(VoiceEntryParser.parse("6 unitati").insulinUnits, 6)
    }

    func testDecimalCommaDose() {
        XCTAssertEqual(VoiceEntryParser.parse("7,5 unități de insulină").insulinUnits, 7.5)
    }

    func testKeywordBeforeNumber() {
        XCTAssertEqual(VoiceEntryParser.parse("insulină 4").insulinUnits, 4)
    }

    // MARK: Glucose

    func testGlucoseKeywordBeforeNumber() {
        XCTAssertEqual(VoiceEntryParser.parse("glicemie 120").spokenGlucose, 120)
    }

    func testGlucoseWithUnitAfter() {
        XCTAssertEqual(VoiceEntryParser.parse("120 mg").spokenGlucose, 120)
        XCTAssertEqual(VoiceEntryParser.parse("5.6 mmol").spokenGlucose, 5.6)
    }

    func testUppercaseUtterance() {
        XCTAssertEqual(VoiceEntryParser.parse("GLICEMIE 140").spokenGlucose, 140)
    }

    // MARK: Other app languages

    func testPolish() {
        XCTAssertEqual(VoiceEntryParser.parse("6 jednostek").insulinUnits, 6)
        XCTAssertEqual(VoiceEntryParser.parse("45 gramów").carbsGrams, 45)
        XCTAssertEqual(VoiceEntryParser.parse("cukier 140").spokenGlucose, 140)
    }

    func testRussian() {
        XCTAssertEqual(VoiceEntryParser.parse("глюкоза 130").spokenGlucose, 130)
        XCTAssertEqual(VoiceEntryParser.parse("6 единиц").insulinUnits, 6)
        XCTAssertEqual(VoiceEntryParser.parse("60 грамм").carbsGrams, 60)
    }

    func testGermanFrenchSpanishDutch() {
        XCTAssertEqual(VoiceEntryParser.parse("4 Einheiten").insulinUnits, 4)
        XCTAssertEqual(VoiceEntryParser.parse("Blutzucker 110").spokenGlucose, 110)
        XCTAssertEqual(VoiceEntryParser.parse("3 unités").insulinUnits, 3)
        XCTAssertEqual(VoiceEntryParser.parse("2 unidades").insulinUnits, 2)
        XCTAssertEqual(VoiceEntryParser.parse("5 eenheden").insulinUnits, 5)
        XCTAssertEqual(VoiceEntryParser.parse("glucose 5,6").spokenGlucose, 5.6)
    }

    // MARK: Combined utterances

    func testCarbsAndInsulinTogether() {
        let result = VoiceEntryParser.parse("60 de grame și 6 unități")
        XCTAssertEqual(result.carbsGrams, 60)
        XCTAssertEqual(result.insulinUnits, 6)
        XCTAssertNil(result.foodDescription)
    }

    func testAllThreeTogether() {
        let result = VoiceEntryParser.parse("glicemie 130, 45 grame orez, 5 unități")
        XCTAssertEqual(result.spokenGlucose, 130)
        XCTAssertEqual(result.carbsGrams, 45)
        XCTAssertEqual(result.foodDescription, "Orez")
        XCTAssertEqual(result.insulinUnits, 5)
    }

    // MARK: Conservatism — no unit word, no entry

    func testBareNumberLogsNothing() {
        XCTAssertTrue(VoiceEntryParser.parse("60").isEmpty)
        XCTAssertTrue(VoiceEntryParser.parse("60 pizza").isEmpty)
    }

    func testEmptyAndNoiseLogNothing() {
        XCTAssertTrue(VoiceEntryParser.parse("").isEmpty)
        XCTAssertTrue(VoiceEntryParser.parse("pizza cu de toate").isEmpty)
    }

    func testFirstValueWinsPerCategory() {
        let result = VoiceEntryParser.parse("60 grame și 30 grame")
        XCTAssertEqual(result.carbsGrams, 60)
    }

    // MARK: Spoken glucose → mg/dL

    func testSpokenGlucoseLargeNumberIsMgdL() {
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 120, preferred: .mgdL), 120)
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 250, preferred: .mmolL), 250)
    }

    func testSpokenGlucoseSmallNumberIsMmol() {
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 5.6, preferred: .mgdL), 100.9, accuracy: 0.05)
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 5.6, preferred: .mmolL), 100.9, accuracy: 0.05)
    }

    func testMmolUserGetsWiderMmolBoundary() {
        // 32 is an extreme-but-possible mmol/L reading for an mmol user…
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 32, preferred: .mmolL), 576.6, accuracy: 0.1)
        // …but for an mg/dL user the same number reads as an (impossibly low,
        // editor-caught) mg/dL value rather than being silently converted.
        XCTAssertEqual(VoiceEntryParser.glucoseMgdL(fromSpoken: 32, preferred: .mgdL), 32, accuracy: 0.1)
    }
}
