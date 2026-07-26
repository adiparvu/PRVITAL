import XCTest
@testable import Prvital

final class LeaderboardTests: XCTestCase {

    func testContinentMapping() {
        XCTAssertEqual(WorldContinents.continent(forCountry: "RO"), "EU")
        XCTAssertEqual(WorldContinents.continent(forCountry: "ro"), "EU")
        XCTAssertEqual(WorldContinents.continent(forCountry: "US"), "NA")
        XCTAssertEqual(WorldContinents.continent(forCountry: "BR"), "SA")
        XCTAssertEqual(WorldContinents.continent(forCountry: "JP"), "AS")
        XCTAssertEqual(WorldContinents.continent(forCountry: "ZA"), "AF")
        XCTAssertEqual(WorldContinents.continent(forCountry: "AU"), "OC")
        XCTAssertEqual(WorldContinents.continent(forCountry: "AQ"), "AN")
        XCTAssertNil(WorldContinents.continent(forCountry: "ZZ"))
    }

    func testFlagEmoji() {
        XCTAssertEqual(WorldContinents.flag(forCountry: "RO"), "🇷🇴")
        XCTAssertEqual(WorldContinents.flag(forCountry: "us"), "🇺🇸")
        XCTAssertEqual(WorldContinents.flag(forCountry: "12"), "")
    }

    func testDefaultsAreOptOut() {
        let prefs = CommunityPreferences.default
        XCTAssertFalse(prefs.enabled)
        XCTAssertTrue(prefs.handle.isEmpty)
    }

    func testEveryScopeHasAName() {
        for scope in LeaderboardScope.allCases {
            XCTAssertFalse(scope.displayName.isEmpty)
        }
    }
}
