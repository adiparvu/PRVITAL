import XCTest
@testable import Prvital

/// What the wrist sends and how the phone treats it: the entry's own time, the
/// exactly-once guarantee, and the outbox that keeps "Logged" honest.
final class WatchEntryRequestTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesAWellFormedEntry() {
        let id = UUID()
        let stamp = now.addingTimeInterval(-90).timeIntervalSince1970
        let request = WatchEntryRequest(payload: ["kind": "insulin", "amount": 4.0, "id": id.uuidString, "ts": stamp])
        XCTAssertEqual(request?.kind, "insulin")
        XCTAssertEqual(request?.amount, 4.0)
        XCTAssertEqual(request?.id, id)
        XCTAssertEqual(request?.sentAt, Date(timeIntervalSince1970: stamp))
    }

    func testAWatchWithoutIdOrStampStillParses() {
        let request = WatchEntryRequest(payload: ["kind": "carbs", "amount": 15.0])
        XCTAssertNotNil(request)
        XCTAssertNil(request?.id)
        XCTAssertNil(request?.sentAt)
    }

    func testRejectsAnythingThatIsNotAnEntry() {
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "weight", "amount": 70.0]))
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "insulin", "amount": 0.0]))
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "insulin", "amount": -2.0]))
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "insulin", "amount": Double.nan]))
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "insulin", "amount": Double.infinity]))
        XCTAssertNil(WatchEntryRequest(payload: ["kind": "insulin"]))
        XCTAssertNil(WatchEntryRequest(payload: ["amount": 4.0]))
        XCTAssertNil(WatchEntryRequest(payload: ["request": "snapshot"]))
    }

    func testAMalformedIdIsTreatedAsNoId() {
        let request = WatchEntryRequest(payload: ["kind": "glucose", "amount": 112.0, "id": "not-a-uuid"])
        XCTAssertNotNil(request)
        XCTAssertNil(request?.id)
    }

    func testThePayloadRoundTrips() {
        let id = UUID()
        let stamp = now.timeIntervalSince1970
        let wire = WatchEntryRequest.payload(kind: "carbs", amount: 20, id: id, stamp: stamp)
        let back = WatchEntryRequest(payload: wire)
        XCTAssertEqual(back, WatchEntryRequest(kind: "carbs", amount: 20, id: id, sentAt: Date(timeIntervalSince1970: stamp)))
    }

    // MARK: When it happened

    func testAQueuedEntryKeepsTheMomentItWasTapped() {
        let tapped = now.addingTimeInterval(-25 * 60)   // phone was away for 25 minutes
        let request = WatchEntryRequest(kind: "insulin", amount: 4, id: UUID(), sentAt: tapped)
        XCTAssertEqual(request.loggedAt(now: now), tapped)
    }

    func testNoStampMeansNow() {
        XCTAssertEqual(WatchEntryRequest(kind: "insulin", amount: 4).loggedAt(now: now), now)
    }

    func testAClockFromTheFutureIsNotTrusted() {
        let future = WatchEntryRequest(kind: "insulin", amount: 4, sentAt: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(future.loggedAt(now: now), now)
        let slightlyAhead = WatchEntryRequest(kind: "insulin", amount: 4, sentAt: now.addingTimeInterval(2 * 60))
        XCTAssertEqual(slightlyAhead.loggedAt(now: now), slightlyAhead.sentAt)
    }

    func testAnAncientStampIsNotTrusted() {
        let old = WatchEntryRequest(kind: "glucose", amount: 100, sentAt: now.addingTimeInterval(-49 * 3600))
        XCTAssertEqual(old.loggedAt(now: now), now)
        let stillFine = WatchEntryRequest(kind: "glucose", amount: 100, sentAt: now.addingTimeInterval(-47 * 3600))
        XCTAssertEqual(stillFine.loggedAt(now: now), stillFine.sentAt)
    }
}

final class WatchEntryLedgerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeLedger() -> WatchEntryLedger {
        let suite = "watch.ledger.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WatchEntryLedger(defaults: defaults)
    }

    func testAnIdIsLoggedOnceNoMatterHowOftenItArrives() {
        let ledger = makeLedger()
        let id = UUID()
        XCTAssertTrue(ledger.claim(id, now: t0))
        XCTAssertFalse(ledger.claim(id, now: t0.addingTimeInterval(1)))
        XCTAssertFalse(ledger.claim(id, now: t0.addingTimeInterval(3600)))
        XCTAssertTrue(ledger.claim(UUID(), now: t0), "a different entry is unaffected")
    }

    func testEntriesWithoutAnIdAlwaysPass() {
        let ledger = makeLedger()
        XCTAssertTrue(ledger.claim(nil, now: t0))
        XCTAssertTrue(ledger.claim(nil, now: t0))
    }

    func testARepeatInsideAWeekIsStillBlocked() {
        let ledger = makeLedger()
        let id = UUID()
        XCTAssertTrue(ledger.claim(id, now: t0))
        XCTAssertFalse(ledger.claim(id, now: t0.addingTimeInterval(6 * 86_400)))
    }

    func testIdsAreForgottenAfterAWeek() {
        let ledger = makeLedger()
        let id = UUID()
        XCTAssertTrue(ledger.claim(id, now: t0))
        XCTAssertTrue(ledger.claim(id, now: t0.addingTimeInterval(8 * 86_400)))
    }

    func testOnlyTheNewestTwoHundredAreKept() {
        let ledger = makeLedger()
        let ids = (0..<205).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            XCTAssertTrue(ledger.claim(id, now: t0.addingTimeInterval(Double(index))))
        }
        let later = t0.addingTimeInterval(300)
        XCTAssertFalse(ledger.claim(ids[204], now: later), "the newest is remembered")
        XCTAssertTrue(ledger.claim(ids[0], now: later), "the oldest fell out of the ledger")
    }
}

@MainActor
final class WatchOutboxTests: XCTestCase {

    func testEntriesWaitUntilThePhoneConfirmsThem() {
        let outbox = WatchOutbox()
        let sending = UUID(), queued = UUID()
        outbox.add(id: sending, kind: "insulin", amount: 4, state: .sending)
        outbox.add(id: queued, kind: "carbs", amount: 15, state: .queued)
        XCTAssertEqual(outbox.waitingCount, 2)

        outbox.markLogged(sending, lingering: .seconds(3600))
        XCTAssertEqual(outbox.state(of: sending), .logged)
        XCTAssertEqual(outbox.waitingCount, 1)

        outbox.markLogged(queued, lingering: .seconds(3600))
        XCTAssertEqual(outbox.waitingCount, 0)
    }

    func testOnlyASendingEntryFallsBackToQueued() {
        let outbox = WatchOutbox()
        let id = UUID()
        outbox.add(id: id, kind: "insulin", amount: 2, state: .sending)
        outbox.markQueued(id)
        XCTAssertEqual(outbox.state(of: id), .queued)

        outbox.markLogged(id, lingering: .seconds(3600))
        outbox.markQueued(id)
        XCTAssertEqual(outbox.state(of: id), .logged, "a confirmed entry never goes back to waiting")
    }

    func testUnknownIdsAreIgnored() {
        let outbox = WatchOutbox()
        outbox.markQueued(UUID())
        outbox.markLogged(UUID(), lingering: .seconds(3600))
        XCTAssertEqual(outbox.waitingCount, 0)
        XCTAssertNil(outbox.state(of: UUID()))
    }
}

/// The wrist can't fetch glucose itself, so what it shows must age on its own.
final class GlucoseSnapshotFreshnessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(minutesOld: Double, mgdL: Double = 120, publishedStale: Bool = false) -> GlucoseSnapshot {
        var snapshot = GlucoseSnapshot()
        snapshot.mgdL = mgdL
        snapshot.valueText = String(Int(mgdL))
        snapshot.updatedAt = now.addingTimeInterval(-minutesOld * 60)
        snapshot.isStale = publishedStale
        return snapshot
    }

    func testAFreshReadingIsNotStale() {
        XCTAssertFalse(snapshot(minutesOld: 3).isStale(at: now))
        XCTAssertFalse(snapshot(minutesOld: 19).isStale(at: now))
    }

    func testAgeAloneTurnsAPublishedFreshReadingStale() {
        // The flag was false when the phone published; two hours later the wrist
        // must still know better.
        let aged = snapshot(minutesOld: 120, publishedStale: false)
        XCTAssertFalse(aged.isStale)
        XCTAssertTrue(aged.isStale(at: now))
        XCTAssertTrue(snapshot(minutesOld: 21).isStale(at: now))
    }

    func testThePublishedStaleFlagStillWins() {
        XCTAssertTrue(snapshot(minutesOld: 1, publishedStale: true).isStale(at: now))
    }

    func testNoReadingIsAlwaysStale() {
        XCTAssertTrue(GlucoseSnapshot().isStale(at: now))
        XCTAssertTrue(GlucoseSnapshot.empty.isStale(at: now))
    }

    // MARK: Smart Stack relevance

    func testALowOutranksEverything() {
        let low = snapshot(minutesOld: 2, mgdL: 58)
        var predicted = snapshot(minutesOld: 2, mgdL: 120)
        predicted.predictionText = "Low predicted in ~20 min"
        let high = snapshot(minutesOld: 2, mgdL: 240)
        let inRange = snapshot(minutesOld: 2, mgdL: 120)

        XCTAssertEqual(low.relevanceScore(at: now), 100)
        XCTAssertEqual(predicted.relevanceScore(at: now), 80)
        XCTAssertEqual(high.relevanceScore(at: now), 60)
        XCTAssertEqual(inRange.relevanceScore(at: now), 10)
        XCTAssertGreaterThan(low.relevanceScore(at: now), predicted.relevanceScore(at: now))
        XCTAssertGreaterThan(predicted.relevanceScore(at: now), high.relevanceScore(at: now))
        XCTAssertGreaterThan(high.relevanceScore(at: now), inRange.relevanceScore(at: now))
    }

    func testAStaleOrMissingReadingIsNeverSurfaced() {
        XCTAssertEqual(snapshot(minutesOld: 90, mgdL: 50).relevanceScore(at: now), 0)
        XCTAssertEqual(GlucoseSnapshot().relevanceScore(at: now), 0)
        XCTAssertEqual(snapshot(minutesOld: 1, mgdL: 0).relevanceScore(at: now), 0)
    }
}
