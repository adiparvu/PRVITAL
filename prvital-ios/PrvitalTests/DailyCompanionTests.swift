import XCTest
@testable import Prvital

final class DailyCompanionTests: XCTestCase {

    private func msg(hasGlucose: Bool = true, tir: Double = 0.6, goal: Double = 0.70,
                     zone: GlucoseZone? = .inRange, streak: Int = 0) -> CompanionMessage {
        DailyCompanion.message(hasGlucose: hasGlucose, tirFraction: tir, goalFraction: goal,
                               currentZone: zone, streakDays: streak)
    }

    func testGettingStartedWhenNoData() {
        XCTAssertEqual(msg(hasGlucose: false).mood, .gettingStarted)
    }

    func testCelebratesWhenMeetingGoal() {
        let m = msg(tir: 0.80, goal: 0.70)
        XCTAssertEqual(m.mood, .celebrating)
    }

    func testGentleNudgeWhenLow() {
        // Below goal but currently low → encouraging, not celebrating.
        let m = msg(tir: 0.40, goal: 0.70, zone: .low)
        XCTAssertEqual(m.mood, .encouraging)
    }

    func testSteadyInTheMiddle() {
        let m = msg(tir: 0.6, goal: 0.70, zone: .inRange)
        XCTAssertEqual(m.mood, .steady)
    }

    func testToughDayStaysKind() {
        let m = msg(tir: 0.2, goal: 0.70, zone: .inRange)
        XCTAssertEqual(m.mood, .encouraging)
        XCTAssertFalse(m.subline.isEmpty)
    }

    func testStreakMentionedOnlyWhenReal() {
        XCTAssertFalse(msg(tir: 0.8, goal: 0.7, streak: 1).subline.contains("streak"))
        XCTAssertTrue(msg(tir: 0.8, goal: 0.7, streak: 5).subline.contains("streak"))
    }
}
