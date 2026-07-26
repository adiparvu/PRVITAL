import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bidirectional WatchConnectivity bridge shared by the app and the watch.
///
///   • Phone → Watch: the latest `GlucoseSnapshot` as the application context,
///     so the watch always shows current glucose even when launched cold.
///   • Watch → Phone: quick insulin / carb entries, which the phone logs through
///     the normal `EntryStore` path (audited, synced, mirrored).
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
    /// Called on the **phone** when the watch requests a quick entry.
    /// `kind` is "insulin" or "carbs"; `amount` is units or grams.
    var onQuickEntry: ((String, Double) -> Void)?

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

    /// Watch → Phone. `transferUserInfo` queues for guaranteed delivery, so quick
    /// entries survive a brief unreachable window without an escaping closure.
    func sendQuickEntry(kind: String, amount: Double) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.transferUserInfo(["kind": kind, "amount": amount])
        #endif
    }

    fileprivate func deliverSnapshot(_ snapshot: GlucoseSnapshot) { onSnapshot?(snapshot) }
    fileprivate func deliverQuickEntry(kind: String, amount: Double) { onQuickEntry?(kind, amount) }
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        forwardQuickEntry(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        forwardQuickEntry(userInfo)
    }

    /// Extracts the Sendable fields in the nonisolated context, then hops to the
    /// main actor to invoke the callback.
    nonisolated private func forwardQuickEntry(_ payload: [String: Any]) {
        guard let kind = payload["kind"] as? String,
              let amount = payload["amount"] as? Double else { return }
        Task { @MainActor in self.deliverQuickEntry(kind: kind, amount: amount) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
