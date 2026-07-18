import XCTest
@testable import Prvital

/// Tests for the Nightscout parsing/normalization layer and its config.
final class NightscoutTests: XCTestCase {

    func testSgvEntryBecomesSample() {
        let entry = NightscoutEntry(id: "abc", sgv: 120, date: 1_700_000_000_000, dateString: nil,
                                    direction: "Flat", device: "xDrip", type: "sgv")
        let sample = entry.asSample()
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.valueMgdL, 120)
        XCTAssertEqual(sample?.id, "abc")
        XCTAssertEqual(sample?.source, .nightscout)
        XCTAssertEqual(sample?.trend, .stable)
        XCTAssertEqual(sample?.deviceID, "xDrip")
        XCTAssertEqual(sample?.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testNonSgvEntryIsDropped() {
        let mbg = NightscoutEntry(id: "x", sgv: nil, date: 1_700_000_000_000, dateString: nil,
                                  direction: nil, device: nil, type: "mbg")
        XCTAssertNil(mbg.asSample())

        let zero = NightscoutEntry(id: "y", sgv: 0, date: 1_700_000_000_000, dateString: nil,
                                   direction: nil, device: nil, type: "sgv")
        XCTAssertNil(zero.asSample())
    }

    func testTrendMapping() {
        XCTAssertEqual(NightscoutEntry.trend(from: "DoubleUp"), .risingFast)
        XCTAssertEqual(NightscoutEntry.trend(from: "SingleUp"), .rising)
        XCTAssertEqual(NightscoutEntry.trend(from: "FortyFiveUp"), .rising)
        XCTAssertEqual(NightscoutEntry.trend(from: "Flat"), .stable)
        XCTAssertEqual(NightscoutEntry.trend(from: "FortyFiveDown"), .falling)
        XCTAssertEqual(NightscoutEntry.trend(from: "SingleDown"), .falling)
        XCTAssertEqual(NightscoutEntry.trend(from: "DoubleDown"), .fallingFast)
        XCTAssertNil(NightscoutEntry.trend(from: "NONE"))
        XCTAssertNil(NightscoutEntry.trend(from: nil))
    }

    func testParseISOToleratesFractionalAndWholeSeconds() {
        XCTAssertNotNil(NightscoutEntry.parseISO("2024-06-01T12:00:00.000Z"))
        XCTAssertNotNil(NightscoutEntry.parseISO("2024-06-01T12:00:00Z"))
        XCTAssertNil(NightscoutEntry.parseISO("not a date"))
    }

    func testDateStringFallbackSynthesizesID() {
        let entry = NightscoutEntry(id: nil, sgv: 100, date: nil, dateString: "2024-06-01T12:00:00.000Z",
                                    direction: "Flat", device: nil, type: "sgv")
        let sample = entry.asSample()
        XCTAssertNotNil(sample)
        XCTAssertTrue(sample?.id.hasPrefix("nightscout-") ?? false)
    }

    func testConfigURLNormalization() {
        XCTAssertEqual(NightscoutConfig(urlString: "mysite.example.com", token: "").normalizedBaseURL?.absoluteString,
                       "https://mysite.example.com")
        XCTAssertEqual(NightscoutConfig(urlString: "https://x.com/", token: "").normalizedBaseURL?.absoluteString,
                       "https://x.com")
        XCTAssertNil(NightscoutConfig(urlString: "   ", token: "").normalizedBaseURL)
        XCTAssertFalse(NightscoutConfig(urlString: "", token: "").isConfigured)
        XCTAssertTrue(NightscoutConfig(urlString: "https://x.com", token: "t").isConfigured)
    }
}
