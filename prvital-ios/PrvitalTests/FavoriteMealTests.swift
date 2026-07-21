import XCTest
@testable import Prvital

final class FavoriteMealTests: XCTestCase {

    private typealias Candidate = FavoriteMealSuggester.Candidate

    private func candidate(
        _ name: String,
        usual: Int? = nil,
        timesUsed: Int = 0,
        lastUsedAt: Date? = nil
    ) -> Candidate {
        Candidate(name: name, usualMinutesFromMidnight: usual, timesUsed: timesUsed, lastUsedAt: lastUsedAt)
    }

    private func names(_ ranked: [Candidate]) -> [String] {
        ranked.map(\.name)
    }

    // MARK: Time-window preference

    func testWithinWindowBeatsMoreUsedOutsideWindow() {
        // Now is 08:00. Breakfast (07:30) is in the ±90 min window; the heavily
        // used dinner (19:00) is not, so breakfast still wins.
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Dinner", usual: 19 * 60, timesUsed: 50),
            candidate("Breakfast", usual: 7 * 60 + 30, timesUsed: 1),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(ranked), ["Breakfast", "Dinner"])
    }

    func testClosestToNowRanksFirstWithinWindow() {
        // Now is 12:00; both are within the window, 11:50 is closer than 12:40.
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Late lunch", usual: 12 * 60 + 40, timesUsed: 99),
            candidate("Early lunch", usual: 11 * 60 + 50, timesUsed: 1),
        ], nowMinutesFromMidnight: 12 * 60)
        XCTAssertEqual(names(ranked), ["Early lunch", "Late lunch"])
    }

    func testExactlyNinetyMinutesAwayIsStillInWindow() {
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Outside", usual: 12 * 60 + 91, timesUsed: 10),
            candidate("Edge", usual: 12 * 60 + 90, timesUsed: 1),
        ], nowMinutesFromMidnight: 12 * 60)
        XCTAssertEqual(names(ranked), ["Edge", "Outside"])
    }

    func testWindowWrapsAroundMidnight() {
        // Now is 00:15; a 23:30 snack is only 45 minutes away across midnight.
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Lunch", usual: 12 * 60, timesUsed: 40),
            candidate("Midnight snack", usual: 23 * 60 + 30, timesUsed: 2),
        ], nowMinutesFromMidnight: 15)
        XCTAssertEqual(names(ranked), ["Midnight snack", "Lunch"])
    }

    func testNoUsualTimeIsTreatedAsOutsideWindow() {
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Never timed", usual: nil, timesUsed: 100),
            candidate("Timed", usual: 8 * 60, timesUsed: 1),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(ranked), ["Timed", "Never timed"])
    }

    // MARK: Tiebreaks

    func testTimesUsedBreaksTiesAtEqualDistance() {
        // Both 30 minutes from now (one before, one after) — usage decides.
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Rarely", usual: 12 * 60 - 30, timesUsed: 2),
            candidate("Often", usual: 12 * 60 + 30, timesUsed: 9),
        ], nowMinutesFromMidnight: 12 * 60)
        XCTAssertEqual(names(ranked), ["Often", "Rarely"])
    }

    func testTimesUsedOrdersFavoritesOutsideTheWindow() {
        let ranked = FavoriteMealSuggester.ranked([
            candidate("B", usual: 20 * 60, timesUsed: 3),
            candidate("A", usual: 21 * 60, timesUsed: 7),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(ranked), ["A", "B"])
    }

    func testLastUsedAtBreaksTimesUsedTies() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Old", timesUsed: 5, lastUsedAt: older),
            candidate("New", timesUsed: 5, lastUsedAt: newer),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(ranked), ["New", "Old"])
        // Never-used sorts after any used favorite.
        let withNil = FavoriteMealSuggester.ranked([
            candidate("Unused", timesUsed: 5, lastUsedAt: nil),
            candidate("Used", timesUsed: 5, lastUsedAt: older),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(withNil), ["Used", "Unused"])
    }

    func testNameIsTheFinalDeterministicTiebreak() {
        let ranked = FavoriteMealSuggester.ranked([
            candidate("Zebra toast"),
            candidate("Apple bowl"),
        ], nowMinutesFromMidnight: 8 * 60)
        XCTAssertEqual(names(ranked), ["Apple bowl", "Zebra toast"])
    }

    // MARK: Clock distance

    func testClockDistanceWrapsAroundMidnight() {
        XCTAssertEqual(FavoriteMealSuggester.clockDistance(23 * 60 + 30, 30), 60)
        XCTAssertEqual(FavoriteMealSuggester.clockDistance(0, 12 * 60), 720)
        XCTAssertEqual(FavoriteMealSuggester.clockDistance(100, 100), 0)
        XCTAssertEqual(FavoriteMealSuggester.clockDistance(10, 1430), 20)
    }

    // MARK: Usual-time blending

    func testFirstUseAdoptsTheNewTime() {
        XCTAssertEqual(FavoriteMealSuggester.blendedUsualMinutes(current: nil, newMinutes: 8 * 60), 8 * 60)
    }

    func testBlendIsTheMidpointOfOldAndNew() {
        // 08:00 usual, logged at 09:00 → drifts to 08:30.
        XCTAssertEqual(
            FavoriteMealSuggester.blendedUsualMinutes(current: 8 * 60, newMinutes: 9 * 60),
            8 * 60 + 30
        )
    }

    func testBlendTakesTheShortWayAroundMidnight() {
        // 23:00 usual, logged at 01:00 → midnight, not noon.
        XCTAssertEqual(FavoriteMealSuggester.blendedUsualMinutes(current: 23 * 60, newMinutes: 60), 0)
        // 00:30 usual, logged at 23:30 → midnight from the other side.
        XCTAssertEqual(FavoriteMealSuggester.blendedUsualMinutes(current: 30, newMinutes: 23 * 60 + 30), 0)
    }

    func testBlendedResultStaysWithinADay() {
        for (current, new) in [(0, 1439), (1439, 0), (720, 720), (1, 1438)] {
            let blended = FavoriteMealSuggester.blendedUsualMinutes(current: current, newMinutes: new)
            XCTAssertTrue((0..<1440).contains(blended), "blend of \(current) and \(new) was \(blended)")
        }
    }

    // MARK: Minutes from midnight

    func testMinutesFromMidnightUsesTheGivenCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2026, month: 7, day: 21, hour: 13, minute: 45)
        let date = cal.date(from: comps)!
        XCTAssertEqual(FavoriteMealSuggester.minutesFromMidnight(of: date, calendar: cal), 13 * 60 + 45)
    }
}
