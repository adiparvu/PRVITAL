import XCTest
@testable import Prvital

/// `ChartExtremes` drives the tide-style peak/valley callouts on the glucose
/// trend chart, so its selection must be deterministic and collision-safe.
final class ChartExtremesTests: XCTestCase {

    /// Builds samples at minute offsets from a fixed reference instant.
    private func samples(_ points: [(minutes: Double, value: Double)]) -> [(date: Date, value: Double)] {
        points.map { (date: date(atMinutes: $0.minutes), value: $0.value) }
    }

    private func date(atMinutes minutes: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: minutes * 60)
    }

    func testEmptyReturnsNothing() {
        XCTAssertTrue(ChartExtremes.find(in: []).isEmpty)
    }

    func testSinglePointReturnsOneExtreme() {
        let result = ChartExtremes.find(in: samples([(0, 120)]))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 120)
        XCTAssertEqual(result[0].date, date(atMinutes: 0))
        XCTAssertEqual(result[0].kind, .peak)
    }

    func testFlatSeriesReturnsSingleExtreme() {
        let flat = samples((0..<8).map { (minutes: Double($0) * 30, value: 110.0) })
        let result = ChartExtremes.find(in: flat)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 110)
        // The first sample represents a run of equal values.
        XCTAssertEqual(result[0].date, date(atMinutes: 0))
    }

    func testMonotoneSeriesReturnsGlobalMaxAndMinOnly() {
        let rising = samples([(0, 80), (60, 100), (120, 130), (180, 170), (240, 210)])
        let result = ChartExtremes.find(in: rising)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kind, .valley)
        XCTAssertEqual(result[0].value, 80)
        XCTAssertEqual(result[0].date, date(atMinutes: 0))
        XCTAssertEqual(result[1].kind, .peak)
        XCTAssertEqual(result[1].value, 210)
        XCTAssertEqual(result[1].date, date(atMinutes: 240))
    }

    func testWavySeriesPicksPeaksAndValleys() {
        let wavy = samples([
            (0, 100), (60, 180), (120, 100), (180, 40), (240, 100), (300, 170), (360, 100),
        ])
        let result = ChartExtremes.find(in: wavy)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.kind), [.peak, .valley, .peak])
        XCTAssertEqual(result.map(\.value), [180, 40, 170])
        XCTAssertEqual(result[2].date, date(atMinutes: 300))
    }

    func testSmallBumpsAreNotAnnotated() {
        // The 120 -> 135 wiggle is only 15 mg/dL deep — below the 25 threshold —
        // so only the global max and min are annotated.
        let series = samples([
            (0, 90), (60, 200), (120, 120), (180, 135), (240, 110), (300, 50),
        ])
        let result = ChartExtremes.find(in: series)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.value), [200, 50])
    }

    func testProminenceThresholdIsConfigurable() {
        let series = samples([
            (0, 90), (60, 200), (120, 120), (180, 135), (240, 110), (300, 50),
        ])
        let result = ChartExtremes.find(in: series, prominenceThreshold: 10)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.value), [200, 120, 135, 50])
    }

    func testSeparationSuppressesCrowdedNeighbors() {
        // The turns 20 and 40 minutes after the global max are prominent, but
        // the 45-minute separation rule keeps their labels away.
        let series = samples([
            (0, 100), (60, 40), (120, 100), (180, 250), (200, 150), (220, 220), (280, 100),
        ])
        let result = ChartExtremes.find(in: series)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.value), [40, 250])
    }

    func testCapsAtFourPreferringProminence() {
        // Three prominent local candidates (prominence 100, 80, 80): the cap
        // admits only two, in prominence order with earlier dates breaking ties.
        let zigzag = samples([
            (0, 100), (60, 240), (120, 60), (180, 200), (240, 100), (300, 180), (360, 90),
        ])
        let result = ChartExtremes.find(in: zigzag)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.value), [240, 60, 200, 100])
        XCTAssertEqual(result.map(\.kind), [.peak, .valley, .peak, .valley])
    }

    func testPlateauPeakUsesFirstSampleOfRun() {
        let series = samples([(0, 100), (60, 180), (90, 180), (120, 100)])
        let result = ChartExtremes.find(in: series)
        let peak = result.first { $0.kind == .peak }
        XCTAssertEqual(peak?.date, date(atMinutes: 60))
        XCTAssertEqual(peak?.value, 180)
    }

    func testUnsortedInputIsSortedByDate() {
        let shuffled = samples([(240, 210), (0, 80), (120, 130), (180, 170), (60, 100)])
        let result = ChartExtremes.find(in: shuffled)
        XCTAssertEqual(result.map(\.value), [80, 210])
        XCTAssertEqual(result.map(\.date), [date(atMinutes: 0), date(atMinutes: 240)])
    }

    func testDeterministic() {
        let wavy = samples([
            (0, 100), (60, 180), (120, 100), (180, 40), (240, 100), (300, 170), (360, 100),
        ])
        XCTAssertEqual(ChartExtremes.find(in: wavy), ChartExtremes.find(in: wavy))
    }
}
