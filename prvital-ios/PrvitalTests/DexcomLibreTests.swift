import XCTest
@testable import Prvital

/// Tests for the Dexcom Share and LibreLinkUp parsing layers (the deterministic
/// parts; the network flows are exercised against the live services).
final class DexcomLibreTests: XCTestCase {

    // MARK: Dexcom Share

    func testDexcomParseWT() throws {
        let noOffset = try XCTUnwrap(DexcomShareParsing.parseWT("/Date(1699999999000)/"))
        XCTAssertEqual(noOffset.timeIntervalSince1970, 1_699_999_999, accuracy: 1e-6)
        // A trailing timezone offset is a display hint only and is ignored.
        let withOffset = try XCTUnwrap(DexcomShareParsing.parseWT("/Date(1699999999000-0800)/"))
        XCTAssertEqual(withOffset.timeIntervalSince1970, 1_699_999_999, accuracy: 1e-6)
        XCTAssertNil(DexcomShareParsing.parseWT("garbage"))
        XCTAssertNil(DexcomShareParsing.parseWT("/Date()/"))
    }

    func testDexcomTrendCodesAndNames() {
        XCTAssertEqual(DexcomShareParsing.trend(.code(1)), .risingFast)
        XCTAssertEqual(DexcomShareParsing.trend(.code(4)), .stable)
        XCTAssertEqual(DexcomShareParsing.trend(.code(7)), .fallingFast)
        XCTAssertNil(DexcomShareParsing.trend(.code(9)))
        XCTAssertEqual(DexcomShareParsing.trend(.name("Flat")), .stable)
        XCTAssertEqual(DexcomShareParsing.trend(.name("DoubleDown")), .fallingFast)
        XCTAssertNil(DexcomShareParsing.trend(.name("NONE")))
        XCTAssertNil(DexcomShareParsing.trend(.unknown))
    }

    func testDexcomEntryDecodesTrendAsIntOrString() throws {
        let intForm = #"[{"Value":120,"WT":"/Date(1699999999000)/","Trend":4}]"#
        let stringForm = #"[{"Value":95,"WT":"/Date(1699999999000)/","Trend":"Flat"}]"#
        let a = try JSONDecoder().decode([DexcomShareEntry].self, from: Data(intForm.utf8))
        let b = try JSONDecoder().decode([DexcomShareEntry].self, from: Data(stringForm.utf8))
        XCTAssertEqual(a.first?.trend, .code(4))
        XCTAssertEqual(b.first?.trend, .name("Flat"))

        let sample = DexcomShareParsing.sample(from: a[0])
        XCTAssertEqual(sample?.valueMgdL, 120)
        XCTAssertEqual(sample?.source, .dexcom)
        XCTAssertEqual(sample?.trend, .stable)
        XCTAssertTrue(sample?.id.hasPrefix("dexcom-") ?? false)
    }

    func testDexcomSampleRejectsNonPositive() {
        let entry = DexcomShareEntry(value: 0, wt: "/Date(1699999999000)/", trend: .code(4))
        XCTAssertNil(DexcomShareParsing.sample(from: entry))
    }

    // MARK: LibreLinkUp

    func testLibreParseTimestampRoundTrips() {
        let input = "6/1/2024 12:00:00 PM"
        guard let date = LibreLinkUpParsing.parseTimestamp(input) else {
            return XCTFail("expected a parsed date")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        XCTAssertEqual(formatter.string(from: date), input)
        XCTAssertNil(LibreLinkUpParsing.parseTimestamp("not a date"))
    }

    func testLibreTrendArrows() {
        XCTAssertEqual(LibreLinkUpParsing.trend(1), .fallingFast)
        XCTAssertEqual(LibreLinkUpParsing.trend(3), .stable)
        XCTAssertEqual(LibreLinkUpParsing.trend(5), .risingFast)
        XCTAssertNil(LibreLinkUpParsing.trend(nil))
        XCTAssertNil(LibreLinkUpParsing.trend(9))
    }

    func testLibreSample() {
        // Timestamp is local wall-clock; FactoryTimestamp is the UTC instant the
        // sample must use.
        let measurement = LibreGlucoseMeasurement(valueInMgPerDl: 132,
                                                  timestamp: "6/1/2024 1:00:00 PM",
                                                  factoryTimestamp: "6/1/2024 12:00:00 PM",
                                                  trendArrow: 3)
        let sample = LibreLinkUpParsing.sample(from: measurement)
        XCTAssertEqual(sample?.valueMgdL, 132)
        XCTAssertEqual(sample?.source, .freeStyleLibre)
        XCTAssertEqual(sample?.trend, .stable)
        XCTAssertTrue(sample?.id.hasPrefix("libre-") ?? false)
        XCTAssertEqual(sample?.timestamp, LibreLinkUpParsing.parseTimestamp("6/1/2024 12:00:00 PM"))
    }

    func testLibreAccountIDHashIsSHA256Hex() {
        // Known SHA-256 of "abc".
        XCTAssertEqual(LibreLinkUpParsing.accountIDHash("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: Credentials

    func testCredentialsCompleteness() {
        XCTAssertTrue(SourceCredentials(username: "a", password: "b").isComplete)
        XCTAssertFalse(SourceCredentials(username: "  ", password: "b").isComplete)
        XCTAssertFalse(SourceCredentials(username: "a", password: "").isComplete)
    }
}
