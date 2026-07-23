import XCTest
@testable import Prvital

final class ContextualLessonTests: XCTestCase {

    func testNilWhenNoReadings() {
        XCTAssertNil(ContextualLesson.make(recentMgdL: [], targetLow: 70, targetHigh: 180))
    }

    func testLowOutranksHigh() {
        // A low earlier is the more urgent thing to learn about, even alongside a high.
        let lesson = ContextualLesson.make(recentMgdL: [200, 60, 150], targetLow: 70, targetHigh: 180)
        XCTAssertEqual(lesson?.situation, .recentLow)
        XCTAssertEqual(lesson?.articleID, "hypoglycaemia")
    }

    func testHighWhenNoLow() {
        let lesson = ContextualLesson.make(recentMgdL: [150, 200, 160], targetLow: 70, targetHigh: 180)
        XCTAssertEqual(lesson?.situation, .recentHigh)
        XCTAssertEqual(lesson?.articleID, "hyperglycaemia")
    }

    func testSteadyWhenInRange() {
        let lesson = ContextualLesson.make(recentMgdL: [90, 120, 140], targetLow: 70, targetHigh: 180)
        XCTAssertEqual(lesson?.situation, .steady)
        XCTAssertEqual(lesson?.articleID, "time-in-range")
    }

    func testBoundaryValuesCountAsInRange() {
        // Exactly on the bounds is in range — not a low or a high.
        let lesson = ContextualLesson.make(recentMgdL: [70, 180], targetLow: 70, targetHigh: 180)
        XCTAssertEqual(lesson?.situation, .steady)
    }
}
