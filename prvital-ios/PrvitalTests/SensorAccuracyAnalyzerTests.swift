import XCTest
@testable import Prvital

final class SensorAccuracyAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func cgm(_ minutes: Double, _ mgdL: Double) -> GlucoseReading {
        GlucoseReading(
            valueMgdL: mgdL,
            timestamp: base.addingTimeInterval(minutes * 60),
            source: .dexcom,
            measurementType: .cgm
        )
    }

    private func meter(
        _ minutes: Double,
        _ mgdL: Double,
        type: GlucoseMeasurementType = .fingerstick
    ) -> GlucoseReading {
        GlucoseReading(
            valueMgdL: mgdL,
            timestamp: base.addingTimeInterval(minutes * 60),
            source: .bloodGlucoseMeter,
            measurementType: type
        )
    }

    /// Five exact-match pairs (ref == cgm, 1 min apart) starting at `startHour`,
    /// spread an hour apart so pairing is unambiguous and every ARD is zero.
    private func cleanPairs(startHour: Double = 10, count: Int = 5) -> [GlucoseReading] {
        (0..<count).flatMap { i -> [GlucoseReading] in
            let t = (startHour + Double(i)) * 60
            return [meter(t, 120), cgm(t + 1, 120)]
        }
    }

    // MARK: MARD math

    func testMARDOnHandComputedPairs() {
        // ref → cgm (1 min later):  ARD        |diff|  15/15?
        // 100 → 110                 0.10        10     yes (10% ≤ 15%)
        // 200 → 180                 0.10        20     yes (10% ≤ 15%)
        //  80 →  90                 0.125       10     yes (ref<100, 10 ≤ 15)
        //  90 → 106                 16/90       16     no  (ref<100, 16 > 15)
        // 150 → 120                 0.20        30     no  (20% > 15%)
        let readings = [
            meter(0, 100), cgm(1, 110),
            meter(60, 200), cgm(61, 180),
            meter(120, 80), cgm(121, 90),
            meter(180, 90), cgm(181, 106),
            meter(240, 150), cgm(241, 120),
        ]
        let result = SensorAccuracyAnalyzer.analyze(readings)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pairCount, 5)
        let expectedMARD = (0.10 + 0.10 + 0.125 + 16.0 / 90.0 + 0.20) / 5 * 100
        XCTAssertEqual(result?.meanAbsoluteRelativeDifferencePercent ?? 0, expectedMARD, accuracy: 1e-9)
        XCTAssertEqual(result?.meanAbsoluteDifferenceMgdL ?? 0, 17.2, accuracy: 1e-9)
        XCTAssertEqual(result?.withinISO15197Fraction ?? 0, 0.6, accuracy: 1e-9)
    }

    func testFewerThanFivePairsReturnsNil() {
        let readings = cleanPairs(count: 4)
        XCTAssertNil(SensorAccuracyAnalyzer.analyze(readings))
    }

    func testNoReferencesOrNoSensorReturnsNil() {
        XCTAssertNil(SensorAccuracyAnalyzer.analyze([]))
        XCTAssertNil(SensorAccuracyAnalyzer.analyze((0..<6).map { cgm(Double($0) * 60, 120) }))
        XCTAssertNil(SensorAccuracyAnalyzer.analyze((0..<6).map { meter(Double($0) * 60, 120) }))
    }

    // MARK: Pairing window

    func testWindowBoundaryFifteenMinutesInclusive() {
        // Each cgm exactly 15:00 after its finger stick — all five pair.
        let readings = (0..<5).flatMap { i -> [GlucoseReading] in
            let t = Double(i) * 60
            return [meter(t, 120), cgm(t + 15, 120)]
        }
        XCTAssertEqual(SensorAccuracyAnalyzer.analyze(readings)?.pairCount, 5)
    }

    func testJustOutsideWindowIsNotPaired() {
        // Four in-window pairs plus one stick whose only cgm is 15 min + 1 s
        // away → only 4 pairs → below the minimum → nil.
        var readings = cleanPairs(count: 4)
        readings.append(meter(0, 100))
        readings.append(cgm(15.0 + 1.0 / 60.0, 100))
        XCTAssertNil(SensorAccuracyAnalyzer.analyze(readings))
    }

    // MARK: One-to-one pairing

    func testNearestReferenceWinsTheSensorReading() {
        // Sticks at 0 min (100) and 4 min (200); one cgm at 3 min (200).
        // Nearest wins → the 200 stick pairs (ARD 0); the 100 stick stays
        // unpaired even though it is also in-window. Wrong pairing would add
        // a 100% ARD.
        let readings = [meter(0, 100), meter(4, 200), cgm(3, 200)] + cleanPairs(count: 4)
        let result = SensorAccuracyAnalyzer.analyze(readings)
        XCTAssertEqual(result?.pairCount, 5)
        XCTAssertEqual(result?.meanAbsoluteRelativeDifferencePercent ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(result?.withinISO15197Fraction ?? 0, 1.0, accuracy: 1e-9)
    }

    func testEachSensorReadingUsedAtMostOnce() {
        // One cgm (100) with sticks at 1 min (100) and 2 min (50). The closer
        // stick takes it; the 50 stick must not re-use it (that would add a
        // 100% ARD and a sixth pair).
        let readings = [cgm(0, 100), meter(1, 100), meter(2, 50)] + cleanPairs(count: 4)
        let result = SensorAccuracyAnalyzer.analyze(readings)
        XCTAssertEqual(result?.pairCount, 5)
        XCTAssertEqual(result?.meanAbsoluteRelativeDifferencePercent ?? -1, 0, accuracy: 1e-9)
    }

    // MARK: 15/15 criterion boundaries

    func testFifteenFifteenAbsoluteBandBelow100() {
        XCTAssertTrue(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 99, cgmMgdL: 114))
        XCTAssertFalse(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 99, cgmMgdL: 114.1))
        XCTAssertTrue(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 99, cgmMgdL: 84))
        XCTAssertFalse(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 99, cgmMgdL: 83.9))
    }

    func testFifteenFifteenRelativeBandAt100AndAbove() {
        XCTAssertTrue(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 100, cgmMgdL: 115))
        XCTAssertFalse(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 100, cgmMgdL: 115.1))
        XCTAssertTrue(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 100, cgmMgdL: 85))
        XCTAssertFalse(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 100, cgmMgdL: 84.9))
        XCTAssertTrue(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 200, cgmMgdL: 230))
        XCTAssertFalse(SensorAccuracyAnalyzer.meetsFifteenFifteen(referenceMgdL: 200, cgmMgdL: 230.5))
    }

    // MARK: Measurement-type selection

    func testManualEntriesCountAsReferences() {
        let readings = (0..<5).flatMap { i -> [GlucoseReading] in
            let t = Double(i) * 60
            return [meter(t, 120, type: .manual), cgm(t + 1, 120)]
        }
        XCTAssertEqual(SensorAccuracyAnalyzer.analyze(readings)?.pairCount, 5)
    }

    func testLaboratoryAndCalibrationAreNotReferences() {
        let readings = (0..<5).flatMap { i -> [GlucoseReading] in
            let t = Double(i) * 60
            return [meter(t, 120, type: .laboratory),
                    meter(t + 2, 120, type: .calibration),
                    cgm(t + 1, 120)]
        }
        XCTAssertNil(SensorAccuracyAnalyzer.analyze(readings))
    }

    func testConflictSupersededReadingsAreIncluded() {
        // Sticks logged next to sensor points typically lose conflict
        // resolution (isActive == false); the analyzer must still use them.
        let readings = cleanPairs(count: 5)
        for reading in readings where reading.measurementType == .fingerstick {
            reading.isActive = false
        }
        XCTAssertEqual(SensorAccuracyAnalyzer.analyze(readings)?.pairCount, 5)
    }
}
