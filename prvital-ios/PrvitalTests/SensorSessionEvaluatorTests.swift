import XCTest
@testable import Prvital

final class SensorSessionEvaluatorTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testWarmup() {
        // 10 minutes into a Dexcom G7 (30-min warm-up) -> warmup.
        let s = SensorSessionEvaluator.status(start: start, kind: .dexcomG7,
                                              now: start.addingTimeInterval(10 * 60))
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertEqual(s.timeRemaining, 20 * 60, accuracy: 1)
    }

    func testActive() {
        // Day 3 of a G7 -> active.
        let s = SensorSessionEvaluator.status(start: start, kind: .dexcomG7,
                                              now: start.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(s.phase, .active)
        XCTAssertGreaterThan(s.progress, 0)
        XCTAssertLessThan(s.progress, 1)
    }

    func testExpiringSoon() {
        // 6 hours before a G7's 10.5-day expiry -> expiring soon.
        let end = start.addingTimeInterval(SensorKind.dexcomG7.lifetime)
        let s = SensorSessionEvaluator.status(start: start, kind: .dexcomG7,
                                              now: end.addingTimeInterval(-6 * 3_600))
        XCTAssertEqual(s.phase, .expiringSoon)
        XCTAssertEqual(s.timeRemaining, 6 * 3_600, accuracy: 1)
    }

    func testExpired() {
        let s = SensorSessionEvaluator.status(start: start, kind: .dexcomG7,
                                              now: start.addingTimeInterval(11 * 86_400))
        XCTAssertEqual(s.phase, .expired)
        XCTAssertEqual(s.timeRemaining, 0, accuracy: 1e-6)
        XCTAssertEqual(s.progress, 1, accuracy: 1e-6)
    }

    func testProgressMonotonic() {
        let early = SensorSessionEvaluator.status(start: start, kind: .dexcomG6,
                                                  now: start.addingTimeInterval(86_400)).progress
        let later = SensorSessionEvaluator.status(start: start, kind: .dexcomG6,
                                                  now: start.addingTimeInterval(5 * 86_400)).progress
        XCTAssertLessThan(early, later)
    }
}
