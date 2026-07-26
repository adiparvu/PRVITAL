import XCTest
@testable import Prvital

final class BadgesTests: XCTestCase {

    func testTierProgressionAndPoints() {
        var inputs = AchievementInputs()
        inputs.loggedMeals = 100   // meals thresholds [1, 25, 100, 500, 1000] → gold

        let standing = BadgeEvaluator.standing(for: BadgeCatalog.family(.meals), inputs)
        XCTAssertEqual(standing.earnedTier, .gold)
        XCTAssertEqual(standing.nextThreshold, 500)
        XCTAssertFalse(standing.isMaxed)
        // Bronze 10 + silver 25 + gold 50.
        XCTAssertEqual(standing.points, 85)
        // 100 → 500 segment starts at 100: zero progress into it yet.
        XCTAssertEqual(standing.progressToNext, 0, accuracy: 0.001)
    }

    func testLockedFamilyHasNoTier() {
        let inputs = AchievementInputs()
        let standing = BadgeEvaluator.standing(for: BadgeCatalog.family(.streak), inputs)
        XCTAssertNil(standing.earnedTier)
        XCTAssertEqual(standing.nextThreshold, 7)
        XCTAssertEqual(standing.points, 0)
    }

    func testMaxedFamily() {
        var inputs = AchievementInputs()
        inputs.sensorSessions = 100   // sensors thresholds [1, 5, 15, 40, 100]
        let standing = BadgeEvaluator.standing(for: BadgeCatalog.family(.sensors), inputs)
        XCTAssertEqual(standing.earnedTier, .diamond)
        XCTAssertNil(standing.nextThreshold)
        XCTAssertTrue(standing.isMaxed)
        XCTAssertEqual(standing.points, 10 + 25 + 50 + 100 + 200)
    }

    func testA1cSingleThresholdSitsAtGold() {
        var inputs = AchievementInputs()
        inputs.bestGmi = 6.8
        let standing = BadgeEvaluator.standing(for: BadgeCatalog.family(.a1c), inputs)
        XCTAssertEqual(standing.earnedTier, .gold)
        XCTAssertTrue(standing.isMaxed)
        XCTAssertEqual(standing.points, BadgeTier.gold.points)

        inputs.bestGmi = 7.4
        let missed = BadgeEvaluator.standing(for: BadgeCatalog.family(.a1c), inputs)
        XCTAssertNil(missed.earnedTier)
    }

    func testTotalPointsSumsFamilies() {
        var inputs = AchievementInputs()
        inputs.loggedMeals = 1      // meals bronze → 10
        inputs.daysWithData = 7     // glucoseDays [1, 7, …] → bronze + silver = 35
        XCTAssertEqual(BadgeEvaluator.totalPoints(inputs), 45)
        XCTAssertEqual(BadgeEvaluator.earnedTierCount(inputs), 3)
    }

    func testEveryFamilyHasSaneThresholds() {
        for family in BadgeCatalog.families {
            XCTAssertFalse(family.thresholds.isEmpty, "\(family.id) has no thresholds")
            XCTAssertEqual(family.thresholds, family.thresholds.sorted(),
                           "\(family.id) thresholds must ascend")
            XCTAssertLessThanOrEqual(family.thresholds.count, BadgeTier.allCases.count)
        }
    }
}
