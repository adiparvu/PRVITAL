import XCTest
@testable import Prvital

/// The backup format's promises: a version-1 file (records only) keeps
/// restoring forever, and every preference shape survives the JSON round trip.
final class JournalBackupCompatibilityTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: Version-1 files

    func testVersionOneFileDecodesWithEmptyNewFamilies() throws {
        let v1 = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z",
         "glucose":[{"id":"11111111-1111-1111-1111-111111111111",
                     "timestamp":"2026-01-01T08:00:00Z","valueMgdL":112,
                     "sourceRaw":"manual","measurementTypeRaw":"manual",
                     "isActive":true}],
         "insulin":[],"carbs":[],"activity":[],"observations":[],
         "medications":[],"ketones":[]}
        """
        let backup = try decoder.decode(JournalBackup.self, from: Data(v1.utf8))
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.glucose.count, 1)
        XCTAssertEqual(backup.glucose[0].valueMgdL, 112)
        XCTAssertTrue(backup.favorites.isEmpty)
        XCTAssertTrue(backup.labResults.isEmpty)
        XCTAssertTrue(backup.sensorSessions.isEmpty)
        XCTAssertNil(backup.profile)
        XCTAssertTrue(backup.settings.isEmpty)
    }

    func testBareMinimumFileDecodes() throws {
        let backup = try decoder.decode(JournalBackup.self, from: Data("{}".utf8))
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.totalCount, 0)
    }

    func testCurrentVersionRoundTrips() throws {
        var original = JournalBackup()
        original.favorites = [.init(
            id: UUID(), name: "Usual breakfast", grams: 45, mealTypeRaw: "breakfast",
            foodDescription: "rye + eggs", usualMinutesFromMidnight: 450,
            timesUsed: 12, lastUsedAt: Date(), createdAt: Date())]
        original.labResults = [.init(id: UUID(), value: 6.8, timestamp: Date(), note: nil)]
        original.settings = ["pref.hapticsEnabled": .bool(false)]

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(JournalBackup.self, from: data)
        XCTAssertEqual(decoded.version, JournalBackup.currentVersion)
        XCTAssertEqual(decoded.favorites.count, 1)
        XCTAssertEqual(decoded.favorites[0].grams, 45)
        XCTAssertEqual(decoded.labResults[0].value, 6.8)
        XCTAssertEqual(decoded.settings["pref.hapticsEnabled"], .bool(false))
    }

    // MARK: Setting values

    func testEverySettingShapeRoundTrips() throws {
        let stamp = Date(timeIntervalSince1970: 1_760_000_000)
        let all: [String: JournalBackup.SettingValue] = [
            "a": .bool(true),
            "b": .int(42),
            "c": .double(0.3),
            "d": .string("aurora"),
            "e": .stringArray(["hero", "tir"]),
            "f": .data(Data([1, 2, 3])),
            "g": .date(stamp),
            "h": .dateDict(["abdomenLeft": stamp]),
        ]
        let data = try encoder.encode(all)
        let decoded = try decoder.decode([String: JournalBackup.SettingValue].self, from: data)
        XCTAssertEqual(decoded, all)
    }

    func testDefaultsTypeDetectionKeepsBoolsAndNumbersApart() {
        XCTAssertEqual(JournalBackup.SettingValue(any: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(JournalBackup.SettingValue(any: NSNumber(value: 7)), .int(7))
        XCTAssertEqual(JournalBackup.SettingValue(any: NSNumber(value: 0.5)), .double(0.5))
        XCTAssertEqual(JournalBackup.SettingValue(any: "x"), .string("x"))
        XCTAssertNil(JournalBackup.SettingValue(any: ["mixed": 1]))
    }
}
