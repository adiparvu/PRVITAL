import XCTest
@testable import Prvital

final class ProfileFormattingTests: XCTestCase {

    func testTwoWordName() {
        XCTAssertEqual(ProfileFormatting.initials(from: "Ada Lovelace"), "AL")
    }

    func testSingleName() {
        XCTAssertEqual(ProfileFormatting.initials(from: "madonna"), "M")
    }

    func testThreeWordsTakesFirstTwo() {
        XCTAssertEqual(ProfileFormatting.initials(from: "Jean Luc Picard"), "JL")
    }

    func testExtraWhitespaceIsIgnored() {
        XCTAssertEqual(ProfileFormatting.initials(from: "  Ana   Maria  "), "AM")
    }

    func testEmptyAndWhitespaceOnlyAreNil() {
        XCTAssertNil(ProfileFormatting.initials(from: ""))
        XCTAssertNil(ProfileFormatting.initials(from: "   "))
    }

    func testNameWithoutLettersIsNil() {
        XCTAssertNil(ProfileFormatting.initials(from: "123 456"))
    }

    func testLeadingNonLetterInWordSkipsToLetter() {
        // "(Al)" -> first letter is A.
        XCTAssertEqual(ProfileFormatting.initials(from: "(Al) Bo"), "AB")
    }

    func testDiacriticsPreserved() {
        XCTAssertEqual(ProfileFormatting.initials(from: "Élodie Ávila"), "ÉÁ")
    }
}
