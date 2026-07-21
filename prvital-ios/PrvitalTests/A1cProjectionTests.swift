import XCTest
@testable import Prvital

final class A1cProjectionTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let week: TimeInterval = 7 * 86_400

    private func point(week w: Int, gmi: Double) -> GMIPoint {
        GMIPoint(weekStart: base.addingTimeInterval(Double(w) * week), gmi: gmi, readingCount: 100)
    }

    /// 90 days expressed on the fit's x axis (weeks).
    private let horizonWeeks = 90.0 / 7.0

    // MARK: Slope / intercept on known series

    func testSlopeAndProjectionOnPerfectLine() {
        // 7.0 + 0.1 per week over 4 weeks; input deliberately unsorted.
        let points = [3, 0, 2, 1].map { point(week: $0, gmi: 7.0 + 0.1 * Double($0)) }
        let result = A1cProjection.project(points)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.slopePerWeek ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 7.0 + 0.1 * (3 + horizonWeeks), accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .ok)
    }

    func testFlatTrendProjectsTheSameValue() {
        let points = (0..<5).map { point(week: $0, gmi: 6.8) }
        let result = A1cProjection.project(points)
        XCTAssertEqual(result?.slopePerWeek ?? 1, 0, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 6.8, accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .ok)
    }

    func testCalendarGapsUseRealSpacing() {
        // Weeks 0, 1 and 3 (week 2 missing) still on a perfect 0.1/week line:
        // x must come from the dates, not the array index.
        let points = [point(week: 0, gmi: 7.0), point(week: 1, gmi: 7.1), point(week: 3, gmi: 7.3)]
        let result = A1cProjection.project(points)
        XCTAssertEqual(result?.slopePerWeek ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 7.0 + 0.1 * (3 + horizonWeeks), accuracy: 1e-9)
    }

    func testUsesOnlyTheLastEightPoints() {
        // Two wild early weeks followed by eight perfectly linear ones — the
        // fit must ignore the first two entirely.
        let wild = [point(week: 0, gmi: 12.0), point(week: 1, gmi: 12.0)]
        let linear = (2...9).map { point(week: $0, gmi: 7.0 + 0.05 * Double($0 - 2)) }
        let result = A1cProjection.project(wild + linear)
        XCTAssertEqual(result?.slopePerWeek ?? 0, 0.05, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 7.0 + 0.05 * (7 + horizonWeeks), accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .ok)
    }

    // MARK: Clamping

    func testProjectionClampedToUpperBound() {
        // +1.0 per week → raw 90-day projection ≈ 21.9 % → clamped to 14.0.
        let points = (0..<3).map { point(week: $0, gmi: 7.0 + Double($0)) }
        let result = A1cProjection.project(points)
        XCTAssertEqual(result?.slopePerWeek ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 14.0, accuracy: 1e-9)
    }

    func testProjectionClampedToLowerBound() {
        // −1.0 per week → raw projection far below zero → clamped to 4.0.
        let points = (0..<3).map { point(week: $0, gmi: 9.0 - Double($0)) }
        let result = A1cProjection.project(points)
        XCTAssertEqual(result?.slopePerWeek ?? 0, -1.0, accuracy: 1e-9)
        XCTAssertEqual(result?.projectedA1cPercent ?? 0, 4.0, accuracy: 1e-9)
    }

    // MARK: Nil cases

    func testNilWithFewerThanThreePoints() {
        XCTAssertNil(A1cProjection.project([]))
        XCTAssertNil(A1cProjection.project([point(week: 0, gmi: 7.0)]))
        XCTAssertNil(A1cProjection.project([point(week: 0, gmi: 7.0), point(week: 1, gmi: 7.2)]))
    }

    // MARK: Confidence heuristic

    func testThreePointsAreLowConfidence() {
        let points = (0..<3).map { point(week: $0, gmi: 7.0) }
        XCTAssertEqual(A1cProjection.project(points)?.confidence, .low)
    }

    func testLargeResidualsAreLowConfidence() {
        // A 7/8 zigzag over four weeks fits a line badly (RMSE ≈ 0.45 > 0.25).
        let points = [
            point(week: 0, gmi: 7.0), point(week: 1, gmi: 8.0),
            point(week: 2, gmi: 7.0), point(week: 3, gmi: 8.0),
        ]
        XCTAssertEqual(A1cProjection.project(points)?.confidence, .low)
    }

    func testCleanFourPointFitIsOkConfidence() {
        // Small residuals (±0.05 around a 0.1/week line) stay under the limit.
        let points = [
            point(week: 0, gmi: 7.05), point(week: 1, gmi: 7.05),
            point(week: 2, gmi: 7.25), point(week: 3, gmi: 7.25),
        ]
        XCTAssertEqual(A1cProjection.project(points)?.confidence, .ok)
    }
}
