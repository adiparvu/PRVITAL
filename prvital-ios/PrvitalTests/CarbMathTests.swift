import XCTest
@testable import Prvital

final class CarbMathTests: XCTestCase {

    func testFreshCarbFullyOnBoard() {
        let now = Date()
        let entries = [CarbEntry(grams: 60, timestamp: now)]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now), 60, accuracy: 1e-6)
    }

    func testHalfAbsorbed() {
        let now = Date()
        // 90 minutes into a 180-minute absorption -> half remaining.
        let entries = [CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-90 * 60))]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now), 30, accuracy: 1e-6)
    }

    func testFullyAbsorbed() {
        let now = Date()
        let entries = [CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-180 * 60))]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now), 0, accuracy: 1e-6)
        let older = [CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-200 * 60))]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: older, at: now), 0, accuracy: 1e-6)
    }

    func testFutureEntryExcluded() {
        let now = Date()
        let entries = [CarbEntry(grams: 60, timestamp: now.addingTimeInterval(10 * 60))]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now), 0, accuracy: 1e-6)
    }

    func testMultipleEntriesSum() {
        let now = Date()
        let entries = [
            CarbEntry(grams: 60, timestamp: now),                                  // 60
            CarbEntry(grams: 40, timestamp: now.addingTimeInterval(-90 * 60)),     // 20
            CarbEntry(grams: 30, timestamp: now.addingTimeInterval(-200 * 60)),    // 0
        ]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now), 80, accuracy: 1e-6)
    }

    func testCustomAbsorptionTime() {
        let now = Date()
        // 30 minutes into a 60-minute absorption -> half remaining.
        let entries = [CarbEntry(grams: 20, timestamp: now.addingTimeInterval(-30 * 60))]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now, absorptionMinutes: 60), 10, accuracy: 1e-6)
    }

    func testNonPositiveAbsorptionIsSafe() {
        let now = Date()
        let entries = [CarbEntry(grams: 60, timestamp: now)]
        XCTAssertEqual(CarbMath.carbsOnBoard(entries: entries, at: now, absorptionMinutes: 0), 0, accuracy: 1e-6)
    }
}
