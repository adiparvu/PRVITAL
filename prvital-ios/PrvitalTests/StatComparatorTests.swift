import XCTest
@testable import Prvital

final class StatComparatorTests: XCTestCase {

    private func stats(readings: Int, timeInRange: Double, average: Double) -> PeriodStatistics {
        var s = PeriodStatistics()
        s.readingCount = readings
        s.timeInRange = timeInRange
        s.average = average
        return s
    }

    func testNoPreviousPeriodIsAbsent() {
        let current = stats(readings: 10, timeInRange: 0.80, average: 120)
        let c = StatComparator.compare(current: current, previous: nil)
        XCTAssertFalse(c.hasPrevious)
        XCTAssertEqual(c.timeInRangeDelta, 0, accuracy: 1e-9)
        XCTAssertEqual(c.averageDelta, 0, accuracy: 1e-9)
    }

    func testPreviousWithoutGlucoseIsAbsent() {
        let current = stats(readings: 10, timeInRange: 0.80, average: 120)
        let previous = PeriodStatistics() // readingCount 0 -> hasGlucose false
        let c = StatComparator.compare(current: current, previous: previous)
        XCTAssertFalse(c.hasPrevious)
    }

    func testImprovementDeltas() {
        let current = stats(readings: 10, timeInRange: 0.80, average: 120)
        let previous = stats(readings: 10, timeInRange: 0.65, average: 140)
        let c = StatComparator.compare(current: current, previous: previous)
        XCTAssertTrue(c.hasPrevious)
        XCTAssertEqual(c.timeInRangeDelta, 0.15, accuracy: 1e-9)
        XCTAssertEqual(c.averageDelta, -20, accuracy: 1e-9)
    }

    func testRegressionDeltas() {
        let current = stats(readings: 5, timeInRange: 0.50, average: 160)
        let previous = stats(readings: 5, timeInRange: 0.70, average: 130)
        let c = StatComparator.compare(current: current, previous: previous)
        XCTAssertTrue(c.hasPrevious)
        XCTAssertEqual(c.timeInRangeDelta, -0.20, accuracy: 1e-9)
        XCTAssertEqual(c.averageDelta, 30, accuracy: 1e-9)
    }

    // MARK: previousDateRange

    func testPreviousDateRangeIsContiguousAndEqualLength() {
        // Fixed anchor so the test is deterministic.
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let current = InsightsInterval.week.dateRange(now: now)
        let previous = InsightsInterval.week.previousDateRange(now: now)

        // The previous window ends exactly where the current one starts.
        XCTAssertEqual(previous.upperBound, current.lowerBound)
        // Equal length (7 days).
        let currentLength = current.upperBound.timeIntervalSince(current.lowerBound)
        let previousLength = previous.upperBound.timeIntervalSince(previous.lowerBound)
        XCTAssertEqual(previousLength, currentLength, accuracy: 1)
    }
}
