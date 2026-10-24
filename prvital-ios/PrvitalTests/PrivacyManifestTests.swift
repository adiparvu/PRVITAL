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

    /// Each bundle that ships needs its OWN manifest. The app's is proven above;
    /// this walks the embedded extensions and the watch app inside the real bundle.
    func testEveryEmbeddedBundleShipsItsOwnManifest() throws {
        guard Bundle.main.bundleIdentifier == "com.prvital.app" else {
            throw XCTSkip("Not hosted by the app bundle")
        }
        let fileManager = FileManager.default
        let plugIns = try XCTUnwrap(Bundle.main.builtInPlugInsURL, "the app embeds its extensions")
        let widgets = plugIns.appendingPathComponent("PrvitalWidgets.appex")
        XCTAssertTrue(fileManager.fileExists(atPath: widgets.path), "the widget extension is embedded")
        XCTAssertTrue(fileManager.fileExists(atPath: widgets.appendingPathComponent("PrivacyInfo.xcprivacy").path),
                      "the widget extension carries its own PrivacyInfo.xcprivacy")

        // The watch app rides inside the iPhone app. It once did not: the app
        // never embedded it, so nothing watch-side shipped. Absence is a failure.
        let watchApp = Bundle.main.bundleURL.appendingPathComponent("Watch/PrvitalWatch.app")
        XCTAssertTrue(fileManager.fileExists(atPath: watchApp.path),
                      "the iPhone app embeds the watch app (Prvital.app/Watch/PrvitalWatch.app)")
        XCTAssertTrue(fileManager.fileExists(atPath: watchApp.appendingPathComponent("PrivacyInfo.xcprivacy").path),
                      "the watch app carries its own PrivacyInfo.xcprivacy")
        let complications = watchApp.appendingPathComponent("PlugIns/PrvitalWatchWidgets.appex")
        XCTAssertTrue(fileManager.fileExists(atPath: complications.path),
                      "the watch app embeds its complications")
        XCTAssertTrue(fileManager.fileExists(atPath: complications.appendingPathComponent("PrivacyInfo.xcprivacy").path),
                      "the watch complications carry their own PrivacyInfo.xcprivacy")
    }

    /// The watch app only works paired to this app, and its pairing key is the
    /// one thing App Store validation cannot guess for us.
    func testTheWatchAppIsPairedToThisApp() throws {
        guard Bundle.main.bundleIdentifier == "com.prvital.app" else {
            throw XCTSkip("Not hosted by the app bundle")
        }
        let info = Bundle.main.bundleURL.appendingPathComponent("Watch/PrvitalWatch.app/Info.plist")
        let data = try Data(contentsOf: info)
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["WKCompanionAppBundleIdentifier"] as? String, "com.prvital.app")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.prvital.app.watchkitapp")
        XCTAssertEqual(plist["CFBundleVersion"] as? String,
                       Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                       "the watch app carries the same build number as the app that contains it")
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
