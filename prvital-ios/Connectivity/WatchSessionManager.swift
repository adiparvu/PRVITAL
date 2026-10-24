import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bidirectional WatchConnectivity bridge shared by the app and the watch.
///
///   • Phone → Watch: the latest `GlucoseSnapshot` as the application context,
///     so the watch always shows current glucose even when launched cold.
///   • Watch → Phone: quick insulin / carb / glucose entries, which the phone
///     logs through the normal `EntryStore` path (audited, synced, mirrored) at
///     the moment they were TAPPED, exactly once, and then confirms.
///   • Watch → Phone: "send me something fresher", answered by the phone
///     syncing and republishing the snapshot.
///
/// `@MainActor` makes the shared singleton concurrency-safe; the
/// `WCSessionDelegate` callbacks are `nonisolated` and decode in the nonisolated
/// context so only `Sendable` values hop to the main actor (mirrors the estate
/// client's `WatchBridge`).
@MainActor
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    /// Called on the **watch** when a fresh snapshot arrives.
    var onSnapshot: ((GlucoseSnapshot) -> Void)?
    /// Called on the **phone** for each NEW entry the watch sends. A repeat of an
    /// id already logged never reaches it. Log at `request.loggedAt()` — the
    /// wrist's own tap time — not at the moment of delivery.
    var onQuickEntry: ((WatchEntryRequest) -> Void)?
    /// Called on the **phone** when the watch asks for a fresher snapshot.
    var onSnapshotRequest: (() -> Void)?

    private override init() { super.init() }

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    /// The last snapshot actually sent, so an unchanged snapshot skips the whole
    /// encode + IPC round trip. `updateApplicationContext` persists the last
    /// context on the system side, so skipping identical resends loses nothing.
    private var lastSentSnapshot: GlucoseSnapshot?

    /// Phone → Watch. Safe to call frequently; only the latest context is kept.
    func updateSnapshot(_ snapshot: GlucoseSnapshot) {
        #if canImport(WatchConnectivity)
        guard snapshot != lastSentSnapshot else { return }
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(["snapshot": data])
        lastSentSnapshot = snapshot
        #endif
    }

    /// Watch → Phone. Returns the entry's id, which `WatchOutbox` follows until
    /// the phone confirms it logged the entry.
    ///
    /// Phone reachable → `sendMessage`, whose reply IS the confirmation. Phone
    /// out of reach (or that message fails) → `transferUserInfo`: queued by the
    /// system with guaranteed delivery, confirmed by the phone with its own
    /// userInfo once the entry is written. Either way the entry carries the
    /// moment it was tapped and a unique id.
    @discardableResult
    func sendQuickEntry(kind: String, amount: Double, now: Date = Date()) -> UUID {
        let id = UUID()
        let stamp = now.timeIntervalSince1970
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            WatchOutbox.shared.add(id: id, kind: kind, amount: amount, state: .queued)
            return id
        }
        let session = WCSession.default
        if session.isReachable {
            WatchOutbox.shared.add(id: id, kind: kind, amount: amount, state: .sending)
            session.sendMessage(
                WatchEntryRequest.payload(kind: kind, amount: amount, id: id, stamp: stamp),
                replyHandler: { @Sendable _ in
                    Task { @MainActor in WatchOutbox.shared.markLogged(id) }
                },
                errorHandler: { @Sendable _ in
                    Task { @MainActor in
                        WatchSessionManager.shared.queueEntry(kind: kind, amount: amount, id: id, stamp: stamp)
                    }
                })
        } else {
            WatchOutbox.shared.add(id: id, kind: kind, amount: amount, state: .queued)
            queueEntry(kind: kind, amount: amount, id: id, stamp: stamp)
        }
        #else
        WatchOutbox.shared.add(id: id, kind: kind, amount: amount, state: .queued)
        #endif
        return id
    }

    /// Hands an entry to the system queue (guaranteed delivery, later).
    fileprivate func queueEntry(kind: String, amount: Double, id: UUID, stamp: TimeInterval) {
        #if canImport(WatchConnectivity)
        WatchOutbox.shared.markQueued(id)
        WCSession.default.transferUserInfo(
            WatchEntryRequest.payload(kind: kind, amount: amount, id: id, stamp: stamp))
        #endif
    }

    /// Watch → Phone: "send me something fresher". Only when the phone can hear
    /// it — otherwise the stale state already tells the truth.
    func requestFreshSnapshot() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: nil, errorHandler: nil)
        #endif
    }

    fileprivate func deliverSnapshot(_ snapshot: GlucoseSnapshot) { onSnapshot?(snapshot) }
    fileprivate func deliverSnapshotRequest() { onSnapshotRequest?() }

    /// Phone: log a request exactly once. A repeat of an id already logged (a
    /// retried transfer) is skipped here — the caller still confirms it, so the
    /// watch stops waiting.
    fileprivate func handleEntry(_ request: WatchEntryRequest) {
        guard WatchEntryLedger.shared.claim(request.id) else { return }
        onQuickEntry?(request)
    }

    /// Phone → Watch: the queued entry with this id is logged.
    fileprivate func sendAck(_ id: UUID) {
        #if canImport(WatchConnectivity)
        WCSession.default.transferUserInfo(["ack": id.uuidString])
        #endif
    }
}

/// WatchConnectivity hands over its reply handler as a non-Sendable closure,
/// though it is safe to call from any thread. The box carries it into the
/// main-actor task that logs the entry, so the reply goes out AFTER the log.
private struct WatchReplyBox: @unchecked Sendable {
    let call: ([String: Any]) -> Void
}

#if canImport(WatchConnectivity)
extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Decode in the nonisolated context so only the Sendable snapshot crosses
        // to the main actor (avoids sending the non-Sendable [String: Any]).
        guard let data = applicationContext["snapshot"] as? Data,
              let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) else { return }
        Task { @MainActor in self.deliverSnapshot(snapshot) }
    }

    /// A message the sender wants answered: an entry is logged first, THEN the
    /// reply goes out, so the watch's "Logged" means it was.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "snapshot" {
            replyHandler([:])
            Task { @MainActor in self.deliverSnapshotRequest() }
            return
        }
        guard let request = WatchEntryRequest(payload: message) else {
            replyHandler(["ok": false])
            return
        }
        let reply = WatchReplyBox(call: replyHandler)
        Task { @MainActor in
            self.handleEntry(request)
            reply.call(["ok": true, "ack": request.id?.uuidString ?? ""])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "snapshot" {
            Task { @MainActor in self.deliverSnapshotRequest() }
            return
        }
        guard let request = WatchEntryRequest(payload: message) else { return }
        Task { @MainActor in self.handleEntry(request) }
    }

    /// Queued traffic. On the phone: an entry to log, confirmed back by userInfo.
    /// On the watch: that confirmation.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let ack = userInfo["ack"] as? String, let id = UUID(uuidString: ack) {
            Task { @MainActor in WatchOutbox.shared.markLogged(id) }
            return
        }
        guard let request = WatchEntryRequest(payload: userInfo) else { return }
        Task { @MainActor in
            self.handleEntry(request)
            if let id = request.id { self.sendAck(id) }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
