import XCTest
@testable import Prvital

/// `DashboardSummary.mgdLAnHourAgo` — the anchor for the gauge's hour trail.
final class DashboardHourTrailTests: XCTestCase {

    /// Five minutes apart, covering the whole three-hour dashboard window.
    private func series(now: Date, minutesBack: Int, value: (Int) -> Double) -> [GlucoseReading] {
        stride(from: minutesBack, through: 0, by: -5).map { minutes in
            GlucoseReading(valueMgdL: value(minutes),
                           timestamp: now.addingTimeInterval(TimeInterval(-minutes * 60)),
                           source: .manual)
        }
    }

    func testPicksTheReadingAnHourBeforeTheCurrentOne() {
        let now = Date()
        // 200 an hour ago, falling 1 mg/dL a minute to 140 now.
        let readings = series(now: now, minutesBack: 180) { 140 + Double($0) }
        let summary = DashboardSummary.make(
            readings: readings, insulin: [], carbs: [], activity: [],
            thresholds: .standard, now: now)

        XCTAssertEqual(summary.current?.valueMgdL, 140)
        XCTAssertEqual(summary.mgdLAnHourAgo, 200)
    }

    /// The window is measured from the reading, not from `now` — otherwise the
    /// trail would silently shrink as the current reading aged.
    func testMeasuresFromTheCurrentReadingNotFromNow() {
        let now = Date()
        // The trace stops 10 minutes ago, so the newest reading is 10 min old.
        let readings = series(now: now, minutesBack: 180) { 140 + Double($0) }
            .filter { $0.timestamp <= now.addingTimeInterval(-10 * 60) }
        let summary = DashboardSummary.make(
            readings: readings, insulin: [], carbs: [], activity: [],
            thresholds: .standard, now: now)

        // Newest is 150 (10 min back); an hour before THAT is 70 min back = 210.
        XCTAssertEqual(summary.current?.valueMgdL, 150)
        XCTAssertEqual(summary.mgdLAnHourAgo, 210)
    }

    /// A gap around the hour mark draws no trail rather than one measured from
    /// whatever happens to survive at the edge of the window.
    func testNoAnchorWhenTheTraceHasAGapAnHourBack() {
        let now = Date()
        let readings = series(now: now, minutesBack: 180) { 140 + Double($0) }
            .filter { reading in
                let minutesBack = -reading.timestamp.timeIntervalSince(now) / 60
                // Nothing between 25 and 100 minutes ago.
                return minutesBack <= 25 || minutesBack >= 100
            }
        let summary = DashboardSummary.make(
            readings: readings, insulin: [], carbs: [], activity: [],
            thresholds: .standard, now: now)

        XCTAssertNil(summary.mgdLAnHourAgo)
    }

    func testNoAnchorWithOnlyOneReading() {
        let now = Date()
        let summary = DashboardSummary.make(
            readings: [GlucoseReading(valueMgdL: 120, timestamp: now, source: .manual)],
            insulin: [], carbs: [], activity: [], thresholds: .standard, now: now)

        XCTAssertNil(summary.mgdLAnHourAgo)
    }

    /// A stale reading gets no trail, for the same reason it gets no velocity:
    /// the dial is not describing "now" any more.
    func testNoAnchorWhenTheCurrentReadingIsStale() {
        let now = Date()
        let readings = series(now: now, minutesBack: 180) { 140 + Double($0) }
            .filter { $0.timestamp <= now.addingTimeInterval(-30 * 60) }
        let summary = DashboardSummary.make(
            readings: readings, insulin: [], carbs: [], activity: [],
            thresholds: .standard, now: now)

        XCTAssertTrue(summary.isStale)
        XCTAssertNil(summary.mgdLAnHourAgo)
    }

    /// A missed reading or two around the hour mark is still fine — the nearest
    /// reading inside the tolerance anchors the trail.
    func testToleratesAFewMissedReadings() {
        let now = Date()
        let readings = series(now: now, minutesBack: 180) { 140 + Double($0) }
            .filter { reading in
                let minutesBack = -reading.timestamp.timeIntervalSince(now) / 60
                // The 55- and 60-minute readings are missing; 65 is the nearest.
                return minutesBack < 55 || minutesBack > 60
            }
        let summary = DashboardSummary.make(
            readings: readings, insulin: [], carbs: [], activity: [],
            thresholds: .standard, now: now)

        XCTAssertEqual(summary.mgdLAnHourAgo, 205)
    }
}
