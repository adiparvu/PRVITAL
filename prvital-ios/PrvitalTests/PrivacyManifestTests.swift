import XCTest
@testable import Prvital

/// The privacy manifest ships inside the app and says what the code really does.
/// If a target stops bundling it, or the declarations drift from the facts in
/// project.yml, this is where it shows up.
final class PrivacyManifestTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        // Only meaningful when the tests run inside the app, which owns the bundle.
        guard Bundle.main.bundleIdentifier == "com.prvital.app" else {
            throw XCTSkip("Not hosted by the app bundle")
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is missing from the app bundle")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTheAppDoesNotTrack() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
    }

    func testEveryRequiredReasonAPITheAppUsesIsDeclared() throws {
        let manifest = try loadManifest()
        let declared = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: Set<String>] = [:]
        for entry in declared {
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            reasons[category] = Set(entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
        }
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1", "1C8F.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
        XCTAssertEqual(reasons.count, 2, "no other required-reason category is declared without being used")
    }

    func testOnlyTheCommunityEntryIsDeclaredAsCollected() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(
            Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }),
            ["NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeOtherUserContent"])
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }
}
