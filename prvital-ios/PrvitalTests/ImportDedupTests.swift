import XCTest
@testable import Prvital

/// Tests the pure import-dedup layer: stable `externalID` keys and the
/// `BulkImportPlanner` that decides which parsed rows are new. No SwiftData.
final class ImportDedupTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func glucoseRow(_ mgdL: Double, at date: Date, source: DataSource = .dexcom) -> ParsedRow {
        ParsedRow(timestamp: date, source: source,
                  record: .glucose(mgdL: mgdL, measurement: .cgm, trend: nil))
    }

    // MARK: ImportKeys

    func testIdenticalInputsProduceIdenticalKey() {
        let a = ImportKeys.externalID(for: .glucose(mgdL: 124, measurement: .cgm, trend: nil),
                                      source: .dexcom, timestamp: t0)
        let b = ImportKeys.externalID(for: .glucose(mgdL: 124, measurement: .cgm, trend: nil),
                                      source: .dexcom, timestamp: t0)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix(ImportKeys.prefix))
    }

    func testKeyVariesByValueSourceAndTime() {
        let base = ImportKeys.externalID(for: .glucose(mgdL: 124, measurement: .cgm, trend: nil),
                                         source: .dexcom, timestamp: t0)
        let otherValue = ImportKeys.externalID(for: .glucose(mgdL: 125, measurement: .cgm, trend: nil),
                                               source: .dexcom, timestamp: t0)
        let otherSource = ImportKeys.externalID(for: .glucose(mgdL: 124, measurement: .cgm, trend: nil),
                                                source: .freeStyleLibre, timestamp: t0)
        let otherTime = ImportKeys.externalID(for: .glucose(mgdL: 124, measurement: .cgm, trend: nil),
                                              source: .dexcom, timestamp: t0.addingTimeInterval(60))
        XCTAssertNotEqual(base, otherValue)
        XCTAssertNotEqual(base, otherSource)
        XCTAssertNotEqual(base, otherTime)
    }

    func testInsulinAndCarbsGetDistinctKinds() {
        let insulin = ImportKeys.externalID(for: .insulin(units: 4.5, type: .rapidActing, context: .mealBolus, name: nil),
                                            source: .dexcom, timestamp: t0)
        let carbs = ImportKeys.externalID(for: .carbs(grams: 45, meal: .lunch, food: nil),
                                          source: .dexcom, timestamp: t0)
        XCTAssertNotEqual(insulin, carbs)
    }

    // MARK: BulkImportPlanner

    func testAllNewWhenNothingExists() {
        let rows = [glucoseRow(100, at: t0), glucoseRow(110, at: t0.addingTimeInterval(300))]
        let plan = BulkImportPlanner.plan(rows: rows, existing: [])
        XCTAssertEqual(plan.toInsert.count, 2)
        XCTAssertEqual(plan.duplicates, 0)
    }

    func testWithinBatchDuplicatesAreCollapsed() {
        let row = glucoseRow(100, at: t0)
        let plan = BulkImportPlanner.plan(rows: [row, row, row], existing: [])
        XCTAssertEqual(plan.toInsert.count, 1)
        XCTAssertEqual(plan.duplicates, 2)
    }

    func testExistingKeysAreSkipped() {
        let row = glucoseRow(100, at: t0)
        let key = ImportKeys.externalID(for: row.record, source: row.source, timestamp: row.timestamp)
        let plan = BulkImportPlanner.plan(rows: [row], existing: [key])
        XCTAssertTrue(plan.toInsert.isEmpty)
        XCTAssertEqual(plan.duplicates, 1)
    }

    func testReimportOfSameFileInsertsNothing() {
        // Simulate a first import, then a second import of the same rows.
        let rows = [
            glucoseRow(100, at: t0),
            glucoseRow(110, at: t0.addingTimeInterval(300)),
            ParsedRow(timestamp: t0, source: .dexcom,
                      record: .insulin(units: 4.5, type: .rapidActing, context: .mealBolus, name: nil)),
        ]
        let first = BulkImportPlanner.plan(rows: rows, existing: [])
        XCTAssertEqual(first.toInsert.count, 3)
        let storedKeys = Set(first.toInsert.map(\.externalID))
        let second = BulkImportPlanner.plan(rows: rows, existing: storedKeys)
        XCTAssertTrue(second.toInsert.isEmpty)
        XCTAssertEqual(second.duplicates, 3)
    }

    func testKeyedRowCarriesTheComputedID() {
        let row = glucoseRow(100, at: t0)
        let plan = BulkImportPlanner.plan(rows: [row], existing: [])
        let expected = ImportKeys.externalID(for: row.record, source: row.source, timestamp: row.timestamp)
        XCTAssertEqual(plan.toInsert.first?.externalID, expected)
    }
}
