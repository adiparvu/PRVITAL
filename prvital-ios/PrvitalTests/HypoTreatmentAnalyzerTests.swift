import XCTest
@testable import Prvital

final class HypoTreatmentAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func treatment(minutes: Double, grams: Double = 12) -> CarbEntry {
        let entry = CarbEntry(grams: grams, timestamp: base.addingTimeInterval(minutes * 60))
        entry.tags = [.hypoFeeling]
        return entry
    }

    private func meal(minutes: Double, grams: Double = 50) -> CarbEntry {
        CarbEntry(grams: grams, timestamp: base.addingTimeInterval(minutes * 60))
    }

    private func reading(minutes: Double, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: base.addingTimeInterval(minutes * 60), source: .manual)
    }

    func testTooFewTreatmentsReturnsNil() {
        let carbs = [treatment(minutes: 0), treatment(minutes: 300)]
        XCTAssertNil(HypoTreatmentAnalyzer.analyze(readings: [], carbs: carbs))
    }

    func testUntaggedMealsAreNotTreatments() {
        let carbs = [meal(minutes: 0), meal(minutes: 100), meal(minutes: 200)]
        XCTAssertNil(HypoTreatmentAnalyzer.analyze(readings: [], carbs: carbs))
    }

    func testMedianGramsAndRise() throws {
        // Three separate lows, treated with 10/12/20 g; each has a baseline
        // reading at the treatment and a response ~18 min later, +40 mg/dL.
        let carbs = [treatment(minutes: 0, grams: 12),
                     treatment(minutes: 300, grams: 10),
                     treatment(minutes: 600, grams: 20)]
        var readings: [GlucoseReading] = []
        for start in [0.0, 300, 600] {
            readings.append(reading(minutes: start - 2, 58))
            readings.append(reading(minutes: start + 18, 98))
        }
        let stats = try XCTUnwrap(HypoTreatmentAnalyzer.analyze(readings: readings, carbs: carbs))
        XCTAssertEqual(stats.treatmentCount, 3)
        XCTAssertEqual(stats.typicalGrams, 12, "median, not mean — one 20 g outlier can't skew it")
        XCTAssertEqual(stats.risesMeasured, 3)
        XCTAssertEqual(try XCTUnwrap(stats.averageRiseMgdL), 40, accuracy: 0.001)
        XCTAssertEqual(stats.episodes, 3)
        XCTAssertEqual(stats.resolvedInOneRound, 3)
    }

    func testBackToBackRoundsCountAsOneEpisode() throws {
        // A stubborn low treated twice 20 min apart, plus two clean one-round
        // lows: 3 episodes, 2 resolved in one round.
        let carbs = [treatment(minutes: 0), treatment(minutes: 20),
                     treatment(minutes: 400), treatment(minutes: 800)]
        let stats = try XCTUnwrap(HypoTreatmentAnalyzer.analyze(readings: [], carbs: carbs))
        XCTAssertEqual(stats.episodes, 3)
        XCTAssertEqual(stats.resolvedInOneRound, 2)
        XCTAssertNil(stats.averageRiseMgdL, "no readings — no rise to report")
    }

    func testRiseNeedsReadingsOnBothSides() throws {
        // Baselines exist but nothing lands in the 12–30 min response window.
        let carbs = [treatment(minutes: 0), treatment(minutes: 300), treatment(minutes: 600)]
        let readings = [reading(minutes: -2, 60), reading(minutes: 298, 55), reading(minutes: 598, 62)]
        let stats = try XCTUnwrap(HypoTreatmentAnalyzer.analyze(readings: readings, carbs: carbs))
        XCTAssertEqual(stats.risesMeasured, 0)
        XCTAssertNil(stats.averageRiseMgdL)
    }
}
