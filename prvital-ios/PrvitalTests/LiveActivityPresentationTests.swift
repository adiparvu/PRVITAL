import XCTest
@testable import Prvital

/// The Dynamic Island's decision layer: which state a reading is in, and which
/// colour, glyph and headline that state wears.
final class LiveActivityPresentationTests: XCTestCase {

    // MARK: - State

    func testInRangeAndFlatIsStable() {
        let state = LiveActivityPresentation.state(
            mgdL: 110, trendSymbol: "arrow.right", targetLowerMgdL: 70, targetUpperMgdL: 180)
        XCTAssertEqual(state, .stable)
    }

    func testInRangeRisingArrowsAreRising() {
        for symbol in ["arrow.up", "arrow.up.right"] {
            let state = LiveActivityPresentation.state(
                mgdL: 150, trendSymbol: symbol, targetLowerMgdL: 70, targetUpperMgdL: 180)
            XCTAssertEqual(state, .rising, "\(symbol) should read as rising")
        }
    }

    func testInRangeFallingArrowsAreFalling() {
        for symbol in ["arrow.down", "arrow.down.right"] {
            let state = LiveActivityPresentation.state(
                mgdL: 90, trendSymbol: symbol, targetLowerMgdL: 70, targetUpperMgdL: 180)
            XCTAssertEqual(state, .falling, "\(symbol) should read as falling")
        }
    }

    /// The safety-critical rule: out of range always wins, so a falling low can
    /// never present as a calm blue "falling".
    func testOutOfRangeOverridesTheTrend() {
        let low = LiveActivityPresentation.state(
            mgdL: 61, trendSymbol: "arrow.down", targetLowerMgdL: 70, targetUpperMgdL: 180)
        XCTAssertEqual(low, .alert)

        let high = LiveActivityPresentation.state(
            mgdL: 250, trendSymbol: "arrow.up", targetLowerMgdL: 70, targetUpperMgdL: 180)
        XCTAssertEqual(high, .alert)

        // Even a *stable* out-of-range reading is an alert, not "steady".
        let flatLow = LiveActivityPresentation.state(
            mgdL: 55, trendSymbol: "arrow.right", targetLowerMgdL: 70, targetUpperMgdL: 180)
        XCTAssertEqual(flatLow, .alert)
    }

    func testTargetBoundariesAreInclusive() {
        XCTAssertEqual(
            LiveActivityPresentation.state(
                mgdL: 70, trendSymbol: "arrow.right", targetLowerMgdL: 70, targetUpperMgdL: 180),
            .stable)
        XCTAssertEqual(
            LiveActivityPresentation.state(
                mgdL: 180, trendSymbol: "arrow.right", targetLowerMgdL: 70, targetUpperMgdL: 180),
            .stable)
    }

    // MARK: - Colour

    func testEachStateHasItsOwnColour() {
        let colours = LiveGlucoseState.allCases.map { LiveActivityPresentation.colorHex(for: $0) }
        XCTAssertEqual(Set(colours).count, LiveGlucoseState.allCases.count,
                       "every glucose state should be visually distinct")
    }

    func testGlucoseKindFollowsTheReadingWhileOtherKindsAreFixed() {
        // The live reading takes its colour from the state...
        XCTAssertEqual(
            LiveActivityPresentation.colorHex(for: .glucose, glucoseState: .rising),
            LiveActivityPresentation.risingHex)
        XCTAssertEqual(
            LiveActivityPresentation.colorHex(for: .glucose, glucoseState: .alert),
            LiveActivityPresentation.alertHex)

        // ...every other presentation has a fixed semantic colour.
        XCTAssertEqual(
            LiveActivityPresentation.colorHex(for: .insulinOnBoard, glucoseState: .stable),
            LiveActivityPresentation.insulinHex)
        XCTAssertEqual(
            LiveActivityPresentation.colorHex(for: .mealLogged, glucoseState: .alert),
            LiveActivityPresentation.carbsHex)
        XCTAssertEqual(
            LiveActivityPresentation.colorHex(for: .alertLow, glucoseState: .stable),
            LiveActivityPresentation.alertHex)
    }

    // MARK: - Glyph

    func testAlertStateSwapsTheDropForAWarningTriangle() {
        XCTAssertEqual(
            LiveActivityPresentation.iconName(for: .glucose, glucoseState: .stable), "drop.fill")
        XCTAssertEqual(
            LiveActivityPresentation.iconName(for: .glucose, glucoseState: .alert),
            "exclamationmark.triangle.fill")
    }

    func testEveryKindHasAGlyph() {
        for kind in LiveActivityKind.allCases {
            XCTAssertFalse(
                LiveActivityPresentation.iconName(for: kind, glucoseState: .stable).isEmpty,
                "\(kind) should have a glyph")
        }
    }

    // MARK: - Headline

    func testAlertHeadlineDistinguishesLowFromHigh() {
        let low = LiveActivityPresentation.headline(for: .alert, isLow: true)
        let high = LiveActivityPresentation.headline(for: .alert, isLow: false)
        XCTAssertNotEqual(low, high)
        XCTAssertFalse(low.isEmpty)
        XCTAssertFalse(high.isEmpty)
    }

    func testEveryStateHasAHeadlineAndCaption() {
        for state in LiveGlucoseState.allCases {
            XCTAssertFalse(LiveActivityPresentation.headline(for: state, isLow: true).isEmpty)
            XCTAssertFalse(LiveActivityPresentation.caption(for: state, isLow: true).isEmpty)
        }
    }

    // MARK: - Progress

    func testProgressFractionRunsFromZeroToOne() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(600)
        XCTAssertEqual(LiveActivityPresentation.progressFraction(
            start: start, end: end, now: start) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(LiveActivityPresentation.progressFraction(
            start: start, end: end, now: start.addingTimeInterval(300)) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiveActivityPresentation.progressFraction(
            start: start, end: end, now: end) ?? -1, 1, accuracy: 1e-9)
    }

    func testProgressFractionClampsAndRejectsEmptyWindows() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(600)
        // Past the end stays at 1, before the start stays at 0.
        XCTAssertEqual(LiveActivityPresentation.progressFraction(
            start: start, end: end, now: end.addingTimeInterval(9999)) ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(LiveActivityPresentation.progressFraction(
            start: start, end: end, now: start.addingTimeInterval(-9999)) ?? -1, 0, accuracy: 1e-9)
        // A zero-length or inverted window has no meaningful progress.
        XCTAssertNil(LiveActivityPresentation.progressFraction(start: start, end: start, now: start))
        XCTAssertNil(LiveActivityPresentation.progressFraction(
            start: end, end: start, now: start))
    }

    // MARK: - Quick statistics

    func testTimeInRangeCountsTheBandInclusively() {
        // 70 and 180 are in range; 60 and 200 are not → 3 of 5.
        let values: [Double] = [60, 70, 120, 180, 200]
        let tir = LiveActivityPresentation.timeInRangePercent(values, lower: 70, upper: 180)
        XCTAssertEqual(tir ?? -1, 60, accuracy: 1e-9)
    }

    func testTimeInRangeIsNilWithoutReadings() {
        XCTAssertNil(LiveActivityPresentation.timeInRangePercent([], lower: 70, upper: 180))
    }

    func testAverageAndDeviation() {
        let values: [Double] = [100, 100, 100, 100]
        XCTAssertEqual(LiveActivityPresentation.average(values) ?? -1, 100, accuracy: 1e-9)
        // No spread at all.
        XCTAssertEqual(LiveActivityPresentation.standardDeviation(values) ?? -1, 0, accuracy: 1e-9)

        // Population standard deviation of [2, 4, 4, 4, 5, 5, 7, 9] is exactly 2.
        let spread: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
        XCTAssertEqual(LiveActivityPresentation.average(spread) ?? -1, 5, accuracy: 1e-9)
        XCTAssertEqual(LiveActivityPresentation.standardDeviation(spread) ?? -1, 2, accuracy: 1e-9)
    }

    func testDeviationNeedsTwoReadings() {
        XCTAssertNil(LiveActivityPresentation.standardDeviation([]))
        XCTAssertNil(LiveActivityPresentation.standardDeviation([120]))
    }
}
