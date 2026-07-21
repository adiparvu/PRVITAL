import XCTest
@testable import Prvital

/// Tests for the pure CSV import parser (`CSVImportParser`). No SwiftData is
/// touched here — only the text → `[ParsedRow]` decoding that a Prvital export
/// must round-trip through.
final class CSVImporterTests: XCTestCase {

    private let header = "record_type,timestamp_utc,source,value,unit,detail"

    private func firstRecord(_ csv: String, line: UInt = #line) -> ParsedRecord? {
        let result = CSVImportParser.parse(csv)
        XCTAssertEqual(result.rows.count, 1, "expected exactly one row", line: line)
        return result.rows.first?.record
    }

    // MARK: Header / blank / comment handling

    func testHeaderBlankAndCommentLinesAreIgnored() {
        let csv = """
        \(header)

        # This is sensitive, share it only with people you trust, and delete copies.
        glucose,2024-06-01T08:00:00Z,Manual entry,124,mg/dL,Sensor
        """
        let result = CSVImportParser.parse(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skipped, 0, "header/blank/comment lines must not count as skipped")
    }

    func testEmptyInputYieldsNothing() {
        let result = CSVImportParser.parse("")
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.skipped, 0)
    }

    // MARK: Timestamp

    func testISO8601TimestampParsedAsUTC() {
        let result = CSVImportParser.parse("\(header)\nglucose,2024-06-01T12:00:00Z,Manual entry,100,mg/dL,Manual")
        XCTAssertEqual(result.rows.first?.timestamp, Date(timeIntervalSince1970: 1_717_243_200))
    }

    // MARK: Glucose (incl. unit conversion)

    func testGlucoseRowMgdL() {
        let record = firstRecord("\(header)\nglucose,2024-06-01T08:00:00Z,Manual entry,124,mg/dL,Sensor \u{00B7} Stable")
        XCTAssertEqual(record, ParsedRecord.glucose(mgdL: 124, measurement: .cgm, trend: .stable))
    }

    func testGlucoseRowMmolConvertsToMgdL() {
        let result = CSVImportParser.parse("\(header)\nglucose,2024-06-01T08:00:00Z,Dexcom,6.9,mmol/L,Manual")
        guard case let .glucose(mgdL, measurement, trend)? = result.rows.first?.record else {
            return XCTFail("expected a glucose record")
        }
        XCTAssertEqual(mgdL, 6.9 * GlucoseUnit.conversionFactor, accuracy: 1e-6)
        XCTAssertEqual(measurement, .manual)
        XCTAssertNil(trend)
        XCTAssertEqual(result.rows.first?.source, .dexcom, "source column decodes from displayName")
    }

    // MARK: Insulin / carbs / activity

    func testInsulinRow() {
        let record = firstRecord("\(header)\ninsulin,2024-06-01T08:00:00Z,Manual entry,4.5,U,Rapid-acting \u{00B7} Meal \u{00B7} NovoRapid")
        XCTAssertEqual(record, ParsedRecord.insulin(units: 4.5, type: .rapidActing, context: .mealBolus, name: "NovoRapid"))
    }

    func testCarbRow() {
        let record = firstRecord("\(header)\ncarbohydrate,2024-06-01T08:00:00Z,Manual entry,30,g,Lunch \u{00B7} Pasta")
        XCTAssertEqual(record, ParsedRecord.carbs(grams: 30, meal: .lunch, food: "Pasta"))
    }

    func testActivityRow() {
        let result = CSVImportParser.parse("\(header)\nactivity,2024-06-01T08:00:00Z,Apple Watch,45,min,Walking \u{00B7} Moderate")
        XCTAssertEqual(result.rows.first?.record, ParsedRecord.activity(type: .walking, minutes: 45, intensity: .moderate))
        XCTAssertEqual(result.rows.first?.source, .appleWatch)
    }

    func testObservationRowSplitsTagsFromText() {
        let record = firstRecord("\(header)\nobservation,2024-06-01T08:00:00Z,Manual entry,,,Stress \u{00B7} Slept poorly")
        XCTAssertEqual(record, ParsedRecord.observation(tags: [.stress], text: "Slept poorly"))
    }

    // MARK: Quoting

    func testQuotedFieldWithCommaIsPreserved() {
        let record = firstRecord("\(header)\ncarbohydrate,2024-06-01T08:00:00Z,Manual entry,30,g,\"Lunch \u{00B7} Rice, beans and eggs\"")
        XCTAssertEqual(record, ParsedRecord.carbs(grams: 30, meal: .lunch, food: "Rice, beans and eggs"))
    }

    func testEscapedQuotesInsideQuotedField() {
        let record = firstRecord("\(header)\ncarbohydrate,2024-06-01T08:00:00Z,Manual entry,15,g,\"Lunch \u{00B7} He said \"\"hi\"\"\"")
        XCTAssertEqual(record, ParsedRecord.carbs(grams: 15, meal: .lunch, food: "He said \"hi\""))
    }

    // MARK: Malformed rows

    func testMalformedRowsAreSkippedAndCounted() {
        let csv = """
        \(header)
        glucose,2024-06-01T08:00:00Z,Manual entry,124,mg/dL,Sensor
        glucose,not-a-date,Manual entry,110,mg/dL,Sensor
        banana,2024-06-01T09:00:00Z,Manual entry,1,mg/dL,x
        glucose,2024-06-01T10:00:00Z,Manual entry,not-a-number,mg/dL,Sensor
        insulin,2024-06-01T11:00:00Z,Manual entry
        carbohydrate,2024-06-01T12:00:00Z,Manual entry,40,g,Dinner
        """
        let result = CSVImportParser.parse(csv)
        XCTAssertEqual(result.rows.count, 2, "two valid rows survive")
        XCTAssertEqual(result.skipped, 4, "bad date, unknown type, bad number and short row are skipped")
    }

    // MARK: Whole-document round trip

    func testMixedDocumentParsesEveryValidType() {
        let csv = """
        \(header)
        glucose,2024-06-01T08:00:00Z,Manual entry,124,mg/dL,Sensor \u{00B7} Stable
        insulin,2024-06-01T08:05:00Z,Manual entry,6,U,Rapid-acting \u{00B7} Meal
        carbohydrate,2024-06-01T08:10:00Z,Manual entry,45,g,Breakfast \u{00B7} Oats
        activity,2024-06-01T18:00:00Z,Manual entry,30,min,Running \u{00B7} High

        # This document contains sensitive personal health information, handle with care.
        """
        let result = CSVImportParser.parse(csv)
        XCTAssertEqual(result.rows.count, 4)
        XCTAssertEqual(result.skipped, 0)
    }
}
