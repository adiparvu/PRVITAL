import XCTest
@testable import Prvital

/// Tests for the pure parts of the Nightscout upload path: wire-format JSON
/// shapes, the manual-only loop guard, watermark filtering and batching. The
/// network calls themselves are deliberately untested.
final class NightscoutUploaderTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)   // fixed instant

    private func json(of value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: Entry JSON shape

    func testGlucoseEntryJSONShape() throws {
        let record = NightscoutGlucoseUpload(valueMgdL: 120.6, timestamp: noon,
                                             trend: .rising, source: .manual)
        let fields = try json(of: NightscoutUploadPayload.entry(from: record))

        XCTAssertEqual(fields["type"] as? String, "sgv")
        XCTAssertEqual(fields["sgv"] as? Int, 121)                       // rounded, not truncated
        XCTAssertEqual(fields["date"] as? Int, 1_700_000_000_000)        // epoch milliseconds
        XCTAssertEqual(fields["direction"] as? String, "SingleUp")
        XCTAssertEqual(fields["device"] as? String, "prvital")

        // The dateString must parse back through the app's own read-side parser
        // to the same instant.
        let dateString = try XCTUnwrap(fields["dateString"] as? String)
        XCTAssertEqual(NightscoutEntry.parseISO(dateString), noon)
    }

    func testDirectionMappingIsInverseOfReadSide() {
        XCTAssertEqual(NightscoutUploadPayload.direction(from: .risingFast), "DoubleUp")
        XCTAssertEqual(NightscoutUploadPayload.direction(from: .rising), "SingleUp")
        XCTAssertEqual(NightscoutUploadPayload.direction(from: .stable), "Flat")
        XCTAssertEqual(NightscoutUploadPayload.direction(from: .falling), "SingleDown")
        XCTAssertEqual(NightscoutUploadPayload.direction(from: .fallingFast), "DoubleDown")
        XCTAssertEqual(NightscoutUploadPayload.direction(from: nil), "NONE")

        // Every non-nil direction round-trips through the fetch-side mapping.
        for trend in GlucoseTrend.allCases {
            let direction = NightscoutUploadPayload.direction(from: trend)
            XCTAssertEqual(NightscoutEntry.trend(from: direction), trend)
        }
    }

    // MARK: Treatment JSON shapes

    func testCarbTreatmentJSONShape() throws {
        let record = NightscoutCarbUpload(grams: 45, timestamp: noon, source: .manual)
        let fields = try json(of: NightscoutUploadPayload.treatment(from: record))

        XCTAssertEqual(fields["eventType"] as? String, "Carb Correction")
        XCTAssertEqual(fields["carbs"] as? Double, 45)
        XCTAssertEqual(fields["device"] as? String, "prvital")
        XCTAssertNil(fields["insulin"], "a carb treatment must not carry an insulin field")
        let createdAt = try XCTUnwrap(fields["created_at"] as? String)
        XCTAssertEqual(NightscoutEntry.parseISO(createdAt), noon)
    }

    func testInsulinTreatmentJSONShape() throws {
        let meal = NightscoutInsulinUpload(units: 4.5, timestamp: noon,
                                           isMealBolus: true, source: .manual)
        let mealFields = try json(of: NightscoutUploadPayload.treatment(from: meal))
        XCTAssertEqual(mealFields["eventType"] as? String, "Meal Bolus")
        XCTAssertEqual(mealFields["insulin"] as? Double, 4.5)
        XCTAssertEqual(mealFields["device"] as? String, "prvital")
        XCTAssertNil(mealFields["carbs"], "an insulin treatment must not carry a carbs field")
        XCTAssertNotNil(mealFields["created_at"])

        let correction = NightscoutInsulinUpload(units: 2, timestamp: noon,
                                                 isMealBolus: false, source: .manual)
        let correctionFields = try json(of: NightscoutUploadPayload.treatment(from: correction))
        XCTAssertEqual(correctionFields["eventType"] as? String, "Correction Bolus")
    }

    // MARK: Manual-only loop guard

    func testEligibleKeepsOnlyManualRecords() {
        let records: [NightscoutGlucoseUpload] = [
            .init(valueMgdL: 100, timestamp: noon, trend: nil, source: .manual),
            .init(valueMgdL: 110, timestamp: noon, trend: nil, source: .nightscout),
            .init(valueMgdL: 120, timestamp: noon, trend: nil, source: .appleHealth),
            .init(valueMgdL: 130, timestamp: noon, trend: nil, source: .dexcom),
        ]
        let kept = NightscoutUploadPlanner.eligible(records, newerThan: nil)
        XCTAssertEqual(kept.map(\.valueMgdL), [100],
                       "only user-entered records may upload — anything else would loop")
    }

    // MARK: Watermark filter

    func testEligibleDropsRecordsAtOrBeforeWatermark() {
        let records: [NightscoutCarbUpload] = [
            .init(grams: 10, timestamp: noon.addingTimeInterval(-60), source: .manual),
            .init(grams: 20, timestamp: noon, source: .manual),               // exactly at watermark
            .init(grams: 30, timestamp: noon.addingTimeInterval(60), source: .manual),
        ]
        let kept = NightscoutUploadPlanner.eligible(records, newerThan: noon)
        XCTAssertEqual(kept.map(\.grams), [30], "only strictly newer records pass")
    }

    func testEligibleWithoutWatermarkKeepsAllManualSortedAscending() {
        let records: [NightscoutInsulinUpload] = [
            .init(units: 3, timestamp: noon.addingTimeInterval(120), isMealBolus: false, source: .manual),
            .init(units: 1, timestamp: noon.addingTimeInterval(-120), isMealBolus: true, source: .manual),
            .init(units: 2, timestamp: noon, isMealBolus: true, source: .manual),
        ]
        let kept = NightscoutUploadPlanner.eligible(records, newerThan: nil)
        XCTAssertEqual(kept.map(\.units), [1, 2, 3], "uploads go up oldest-first")
    }

    func testWindowStartUsesWatermarkButCapsAtSevenDays() {
        let now = noon
        // No watermark yet: the window floor is exactly 7 days back.
        XCTAssertEqual(NightscoutUploadPlanner.windowStart(watermark: nil, now: now),
                       now.addingTimeInterval(-7 * 24 * 60 * 60))
        // A recent watermark wins over the floor.
        let recent = now.addingTimeInterval(-3600)
        XCTAssertEqual(NightscoutUploadPlanner.windowStart(watermark: recent, now: now), recent)
        // An ancient watermark is capped at the 7-day floor.
        let ancient = now.addingTimeInterval(-30 * 24 * 60 * 60)
        XCTAssertEqual(NightscoutUploadPlanner.windowStart(watermark: ancient, now: now),
                       now.addingTimeInterval(-7 * 24 * 60 * 60))
    }

    // MARK: Batching

    func testChunkedSplitsIntoBatchesOfAtMost100() {
        let items = Array(0..<250)
        let chunks = NightscoutUploadPlanner.chunked(items)
        XCTAssertEqual(chunks.map(\.count), [100, 100, 50])
        XCTAssertEqual(chunks.flatMap { $0 }, items, "chunking must preserve order")
        XCTAssertTrue(NightscoutUploadPlanner.chunked([Int]()).isEmpty)
        XCTAssertEqual(NightscoutUploadPlanner.chunked([1, 2], size: 5), [[1, 2]])
    }
}
