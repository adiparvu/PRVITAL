import XCTest
@testable import Prvital

final class ConflictResolverTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(
        _ mgdL: Double,
        secondsFromBase: TimeInterval = 0,
        source: DataSource,
        type: GlucoseMeasurementType
    ) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL,
                       timestamp: base.addingTimeInterval(secondsFromBase),
                       source: source,
                       measurementType: type)
    }

    /// The reported bug: a finger-stick logged while Dexcom was streaming was
    /// superseded by the sensor sample beside it and vanished from the journal.
    func testFingerstickBeatsCGMFromThePrimarySource() {
        let sensor = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let finger = reading(96, secondsFromBase: 60, source: .manual, type: .fingerstick)

        ConflictResolver().resolve([sensor, finger])

        XCTAssertTrue(finger.isActive, "a blood measurement must never lose to interstitial CGM")
        XCTAssertFalse(sensor.isActive)
        XCTAssertEqual(finger.conflictGroupID, sensor.conflictGroupID)
        XCTAssertNotNil(sensor.resolutionReason, "the superseded sample stays queryable with a reason")
    }

    func testLabResultBeatsEverything() {
        let sensor = reading(150, source: .dexcom, type: .cgm)
        let finger = reading(140, secondsFromBase: 30, source: .bloodGlucoseMeter, type: .fingerstick)
        let lab = reading(138, secondsFromBase: 60, source: .manual, type: .laboratory)

        ConflictResolver().resolve([sensor, finger, lab])

        XCTAssertTrue(lab.isActive)
        XCTAssertFalse(finger.isActive)
        XCTAssertFalse(sensor.isActive)
    }

    /// The de-duplication that source priority exists for is untouched: two
    /// feeds mirroring the same sensor tie on measurement type, so the user's
    /// primary source still decides.
    func testPrimarySourceStillDecidesBetweenTwoCGMFeeds() {
        let dexcom = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let nightscout = reading(151, secondsFromBase: 30, source: .nightscout, type: .cgm)

        ConflictResolver().resolve([dexcom, nightscout])

        XCTAssertTrue(dexcom.isActive, "Dexcom outranks Nightscout in the default priority")
        XCTAssertFalse(nightscout.isActive)
    }

    func testUserPriorityOverridesTheDefaultBetweenCGMFeeds() {
        let dexcom = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let nightscout = reading(151, secondsFromBase: 30, source: .nightscout, type: .cgm)

        ConflictResolver(sourcePriority: [.nightscout, .dexcom]).resolve([dexcom, nightscout])

        XCTAssertTrue(nightscout.isActive)
        XCTAssertFalse(dexcom.isActive)
    }

    /// An untyped quick-logged value carries no measurement authority, so a
    /// real sensor sample beside it still wins.
    func testUntypedManualValueLosesToCGM() {
        let sensor = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let typed = reading(120, secondsFromBase: 30, source: .manual, type: .manual)

        ConflictResolver().resolve([sensor, typed])

        XCTAssertTrue(sensor.isActive)
        XCTAssertFalse(typed.isActive)
    }

    func testReadingsFurtherApartThanTheWindowNeverConflict() {
        let sensor = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let finger = reading(96, secondsFromBase: 600, source: .manual, type: .fingerstick)

        ConflictResolver().resolve([sensor, finger])

        XCTAssertTrue(sensor.isActive)
        XCTAssertTrue(finger.isActive)
        XCTAssertNil(sensor.conflictGroupID)
        XCTAssertNil(finger.conflictGroupID)
    }

    func testResolutionIsIndependentOfInputOrder() {
        func winnerValue(_ readings: [GlucoseReading]) -> Double? {
            ConflictResolver().resolve(readings)
            return readings.first(where: \.isActive)?.valueMgdL
        }
        let forward = [reading(150, source: .dexcom, type: .cgm),
                       reading(96, secondsFromBase: 60, source: .manual, type: .fingerstick)]
        let reversed = [reading(96, secondsFromBase: 60, source: .manual, type: .fingerstick),
                        reading(150, source: .dexcom, type: .cgm)]
        XCTAssertEqual(winnerValue(forward), 96)
        XCTAssertEqual(winnerValue(reversed), 96)
    }

    /// Re-running the pass over an already-resolved cluster must not flip it —
    /// this is what makes the one-time repair safe to run on every cluster.
    func testResolutionIsIdempotent() {
        let sensor = reading(150, secondsFromBase: 0, source: .dexcom, type: .cgm)
        let finger = reading(96, secondsFromBase: 60, source: .manual, type: .fingerstick)
        let cluster = [sensor, finger]

        ConflictResolver().resolve(cluster)
        let firstGroup = finger.conflictGroupID
        ConflictResolver().resolve(cluster)

        XCTAssertTrue(finger.isActive)
        XCTAssertFalse(sensor.isActive)
        XCTAssertNotNil(firstGroup)
    }

    /// A cluster that loses its rival (the sensor sample deleted, say) resets
    /// cleanly instead of staying flagged as conflicted.
    func testSingletonResets() {
        let finger = reading(96, source: .manual, type: .fingerstick)
        finger.isActive = false
        finger.conflictGroupID = UUID()
        finger.resolutionReason = "Superseded — stale"

        ConflictResolver().resolve([finger])

        XCTAssertTrue(finger.isActive)
        XCTAssertNil(finger.conflictGroupID)
        XCTAssertNil(finger.resolutionReason)
    }
}
