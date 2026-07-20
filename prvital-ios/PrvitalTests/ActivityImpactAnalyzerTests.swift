import XCTest
@testable import Prvital

final class ActivityImpactAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(_ minutes: Double, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: base.addingTimeInterval(minutes * 60), source: .manual)
    }

    private func session(_ startMinutes: Double, durationMinutes: Int) -> ActivityEntry {
        ActivityEntry(activityType: .running,
                      startTimestamp: base.addingTimeInterval(startMinutes * 60),
                      durationSeconds: durationMinutes * 60)
    }

    func testBasicDrop() throws {
        let sessions = [session(0, durationMinutes: 30)] // window ends at 30+60 = 90 min
        let readings = [
            reading(-5, 140),  // baseline
            reading(15, 120),
            reading(40, 100),  // nadir
            reading(70, 110),
            reading(120, 60),  // beyond window, ignored
        ]
        let impacts = ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings)
        let impact = try XCTUnwrap(impacts.first)
        XCTAssertEqual(impact.baselineMgdL, 140, accuracy: 1e-9)
        XCTAssertEqual(impact.nadirMgdL, 100, accuracy: 1e-9)
        XCTAssertEqual(impact.deltaMgdL, -40, accuracy: 1e-9)
        XCTAssertEqual(impact.minutesToNadir, 40)
    }

    func testSessionWithoutBaselineIsSkipped() {
        let sessions = [session(0, durationMinutes: 30)]
        let readings = [reading(15, 120), reading(40, 100)] // nothing near the start
        XCTAssertTrue(ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings).isEmpty)
    }

    func testSessionWithoutPostReadingIsSkipped() {
        let sessions = [session(0, durationMinutes: 30)]
        let readings = [reading(-3, 130)] // baseline only
        XCTAssertTrue(ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings).isEmpty)
    }

    func testZeroDurationSessionsIgnored() {
        let sessions = [ActivityEntry(activityType: .walking, startTimestamp: base, durationSeconds: 0)]
        let readings = [reading(-3, 130), reading(20, 110)]
        XCTAssertTrue(ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings).isEmpty)
    }

    func testSummaryAveragesChange() {
        let sessions = [session(0, durationMinutes: 30), session(180, durationMinutes: 30)]
        var readings: [GlucoseReading] = []
        readings += [reading(-3, 140), reading(40, 100)]                 // drop 40
        readings += [reading(180 - 3, 120), reading(180 + 40, 100)]      // drop 20
        let impacts = ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings)
        XCTAssertEqual(impacts.count, 2)
        let summary = ActivityImpactAnalyzer.summary(impacts)
        XCTAssertEqual(summary?.count, 2)
        XCTAssertEqual(summary?.averageChangeMgdL ?? 0, -30, accuracy: 1e-9) // (-40 + -20)/2
    }

    func testEmptySummaryIsNil() {
        XCTAssertNil(ActivityImpactAnalyzer.summary([]))
    }
}
