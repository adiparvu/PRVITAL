import XCTest
@testable import Prvital

final class DataGapDetectorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func r(_ minutes: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: 100, timestamp: base.addingTimeInterval(minutes * 60), source: .manual)
    }

    func testDetectsSingleGap() {
        // 5→45 is a 40-min gap; the 5-min steps are not.
        let stats = DataGapDetector.analyze([r(0), r(5), r(45), r(50)])
        XCTAssertEqual(stats?.gapCount, 1)
        XCTAssertEqual(stats?.longestGapMinutes ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(stats?.totalGapMinutes ?? 0, 40, accuracy: 1e-9)
    }

    func testMultipleGapsTrackLongestAndTotal() {
        // deltas: 5, 55, 30, 60 → gaps over 30 are 55 and 60 (30 is not > 30).
        let stats = DataGapDetector.analyze([r(0), r(5), r(60), r(90), r(150)])
        XCTAssertEqual(stats?.gapCount, 2)
        XCTAssertEqual(stats?.longestGapMinutes ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(stats?.totalGapMinutes ?? 0, 115, accuracy: 1e-9)
    }

    func testNoGapsIsNil() {
        XCTAssertNil(DataGapDetector.analyze([r(0), r(5), r(10), r(15)]))
    }

    func testFewerThanTwoIsNil() {
        XCTAssertNil(DataGapDetector.analyze([r(0)]))
        XCTAssertNil(DataGapDetector.analyze([]))
    }

    func testCustomThreshold() {
        // With a 10-min threshold, the 5→20 (15-min) step becomes a gap.
        let stats = DataGapDetector.analyze([r(0), r(5), r(20)], gapThresholdMinutes: 10)
        XCTAssertEqual(stats?.gapCount, 1)
        XCTAssertEqual(stats?.longestGapMinutes ?? 0, 15, accuracy: 1e-9)
    }
}
