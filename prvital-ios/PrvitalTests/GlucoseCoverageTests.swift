import XCTest
@testable import Prvital

final class GlucoseCoverageTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60

    func testFullCoverage() {
        // 288 readings at 5-min cadence over a day == 100%.
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 288, window: day), 1, accuracy: 1e-9)
    }

    func testHalfCoverage() {
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 144, window: day), 0.5, accuracy: 1e-9)
    }

    func testCoverageClampedToOne() {
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 400, window: day), 1, accuracy: 1e-9)
    }

    func testEmptyInputsAreZero() {
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 0, window: day), 0, accuracy: 1e-9)
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 100, window: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(GlucoseCoverage.coverage(readingCount: 100, window: day, cadenceMinutes: 0), 0, accuracy: 1e-9)
    }

    func testReliabilityThreshold() {
        XCTAssertTrue(GlucoseCoverage.isReliable(0.70))
        XCTAssertTrue(GlucoseCoverage.isReliable(0.85))
        XCTAssertFalse(GlucoseCoverage.isReliable(0.69))
    }
}
