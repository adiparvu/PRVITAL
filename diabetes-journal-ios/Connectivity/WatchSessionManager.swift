import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bidirectional WatchConnectivity bridge shared by the app and the watch.
///
///   • Phone → Watch: the latest `GlucoseSnapshot` as the application context,
///     so the watch always shows current glucose even when launched cold.
///   • Watch → Phone: quick insulin / carb entries as messages, which the phone
///     logs through the normal `EntryStore` path (audited, synced, mirrored).
///
/// Both sides use the one type; the closures wired on each platform differ.
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

    /// Phone → Watch. Safe to call frequently; only the latest context is kept.
    func updateSnapshot(_ snapshot: GlucoseSnapshot) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(["snapshot": data])
        #endif
    }

    /// Watch → Phone. Uses a message with a userInfo fallback when unreachable.
    func sendQuickEntry(kind: String, amount: Double) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = ["kind": kind, "amount": amount]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliverSnapshot(from: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliverQuickEntry(from: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliverQuickEntry(from: userInfo)
    }

    private func deliverSnapshot(from context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
    }

    private func deliverQuickEntry(from payload: [String: Any]) {
        guard let kind = payload["kind"] as? String, let amount = payload["amount"] as? Double else { return }
        DispatchQueue.main.async { [weak self] in self?.onQuickEntry?(kind, amount) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
