import XCTest
@testable import Prvital

final class PeriodTIRTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func reading(hour: Int, _ mgdL: Double) -> GlucoseReading {
        var dc = DateComponents(); dc.year = 2026; dc.month = 6; dc.day = 15; dc.hour = hour
        return GlucoseReading(valueMgdL: mgdL, timestamp: cal.date(from: dc)!, source: .manual)
    }

    func testBucketsByPeriodAndComputesTIR() {
        let readings = [
            reading(hour: 2, 100),                       // overnight, in range
            reading(hour: 8, 100), reading(hour: 8, 300), // morning: 1 in range, 1 high
            reading(hour: 20, 300),                      // evening, high
        ]
        let b = PeriodTIRAnalyzer.breakdown(
            readings, thresholds: .standard, targets: .default,
            globalTargetPercent: 70, calendar: cal)
        let byPeriod = Dictionary(uniqueKeysWithValues: b.map { ($0.period, $0) })
        XCTAssertEqual(byPeriod[.overnight]?.timeInRange ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(byPeriod[.overnight]?.readingCount, 1)
        XCTAssertEqual(byPeriod[.morning]?.timeInRange ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(byPeriod[.morning]?.readingCount, 2)
        XCTAssertFalse(byPeriod[.afternoon]?.hasData ?? true)
        XCTAssertEqual(byPeriod[.evening]?.timeInRange ?? -1, 0, accuracy: 1e-9)
    }

    func testAlwaysReturnsAllFourPeriods() {
        let b = PeriodTIRAnalyzer.breakdown(
            [], thresholds: .standard, targets: .default,
            globalTargetPercent: 70, calendar: cal)
        XCTAssertEqual(b.count, 4)
        XCTAssertTrue(b.allSatisfy { !$0.hasData })
    }

    func testGlobalTargetUsedWhenDisabled() {
        let b = PeriodTIRAnalyzer.breakdown(
            [reading(hour: 2, 100)], thresholds: .standard, targets: .default,
            globalTargetPercent: 80, calendar: cal)
        let overnight = b.first { $0.period == .overnight }!
        XCTAssertEqual(overnight.targetFraction, 0.8, accuracy: 1e-9)
        XCTAssertTrue(overnight.met) // TIR 1.0 ≥ 0.8
    }

    func testPerPeriodTargetsWhenEnabled() {
        var targets = PeriodTIRTargets.default
        targets.enabled = true
        targets.morningPercent = 40
        let b = PeriodTIRAnalyzer.breakdown(
            [reading(hour: 8, 100), reading(hour: 8, 300)], // morning TIR 0.5
            thresholds: .standard, targets: targets,
            globalTargetPercent: 70, calendar: cal)
        let morning = b.first { $0.period == .morning }!
        XCTAssertEqual(morning.targetFraction, 0.4, accuracy: 1e-9)
        XCTAssertTrue(morning.met) // 0.5 ≥ 0.4
    }

    func testTargetsTolerantDecodePreservesDefaults() {
        // An older / partial payload missing newer keys must keep saved values and
        // fall back to defaults for the rest — never zeroing a target.
        let json = #"{"enabled":true,"overnightPercent":85}"#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(PeriodTIRTargets.self, from: json)
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.overnightPercent, 85, accuracy: 1e-9)
        XCTAssertEqual(decoded.morningPercent, 70, accuracy: 1e-9) // default preserved
    }
}
