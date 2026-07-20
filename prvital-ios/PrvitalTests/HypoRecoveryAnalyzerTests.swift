import XCTest
@testable import Prvital

final class HypoRecoveryAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func r(_ minutes: Double, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: base.addingTimeInterval(minutes * 60), source: .manual)
    }

    func testSingleRecovery() {
        // Low from 10 min, back in range at 30 min -> 20 minutes.
        let readings = [r(0, 120), r(10, 60), r(20, 65), r(30, 100), r(60, 110)]
        let stats = HypoRecoveryAnalyzer.analyze(readings, thresholds: .standard)
        XCTAssertEqual(stats?.episodeCount, 1)
        XCTAssertEqual(stats?.averageMinutes ?? 0, 20, accuracy: 1e-9)
    }

    func testUnrecoveredLowIsIgnored() {
        let readings = [r(0, 120), r(10, 60), r(20, 55)] // still low at the end
        XCTAssertNil(HypoRecoveryAnalyzer.analyze(readings, thresholds: .standard))
    }

    func testNoLowsIsNil() {
        let readings = [r(0, 100), r(10, 120), r(20, 110)]
        XCTAssertNil(HypoRecoveryAnalyzer.analyze(readings, thresholds: .standard))
    }

    func testMultipleEpisodesAveraged() {
        let readings = [
            r(0, 120), r(10, 60), r(30, 100),   // recovery 20 min
            r(50, 120), r(60, 65), r(100, 110), // recovery 40 min
        ]
        let stats = HypoRecoveryAnalyzer.analyze(readings, thresholds: .standard)
        XCTAssertEqual(stats?.episodeCount, 2)
        XCTAssertEqual(stats?.averageMinutes ?? 0, 30, accuracy: 1e-9) // (20+40)/2
    }
}
