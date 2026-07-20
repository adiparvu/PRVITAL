import XCTest
@testable import Prvital

final class GlucoseUnitLocaleTests: XCTestCase {

    func testMmolRegions() {
        for region in ["GB", "IE", "CA", "AU", "NZ", "NL", "RU", "SE", "CN"] {
            XCTAssertEqual(GlucoseUnit.localeDefault(regionCode: region), .mmolL, "\(region) should default to mmol/L")
        }
    }

    func testMgdLRegions() {
        for region in ["US", "DE", "FR", "IT", "ES", "PT", "JP", "IL"] {
            XCTAssertEqual(GlucoseUnit.localeDefault(regionCode: region), .mgdL, "\(region) should default to mg/dL")
        }
    }

    func testCaseInsensitive() {
        XCTAssertEqual(GlucoseUnit.localeDefault(regionCode: "gb"), .mmolL)
    }

    func testUnknownAndNilFallBackToMgdL() {
        XCTAssertEqual(GlucoseUnit.localeDefault(regionCode: "ZZ"), .mgdL)
        XCTAssertEqual(GlucoseUnit.localeDefault(regionCode: nil), .mgdL)
    }
}
