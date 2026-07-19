import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Delivers reactive glucose alerts. It owns the notification center and the
/// persisted `GlucoseAlertState`; the *decision* of whether to alert is made by
/// the pure `GlucoseAlertEvaluator`, so this type only fetches state, calls the
/// evaluator, and fires a local notification when told to.
@MainActor
final class GlucoseAlertService {
    private let defaults: UserDefaults
    private static let stateKey = "glucose.alertState"

    #if canImport(UserNotifications)
    private let center = UNUserNotificationCenter.current()
    #endif

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    /// Evaluates the current reading and fires a notification if warranted.
    /// Called after any data change once the snapshot is rebuilt.
    func evaluate(
        current: GlucoseAlertEvaluator.Reading?,
        thresholds: GlucoseThresholds,
        preferences: AlertPreferences,
        unit: GlucoseUnit,
        now: Date = Date()
    ) {
        guard preferences.enabled, let current else { return }
        let decision = GlucoseAlertEvaluator.decide(
            reading: current, thresholds: thresholds, preferences: preferences,
            unit: unit, last: loadState(), now: now
        )
        if let alert = decision.alert { fire(alert) }
        saveState(decision.state)
    }

    // MARK: State

    private func loadState() -> GlucoseAlertState {
        guard let data = defaults.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(GlucoseAlertState.self, from: data)
        else { return .empty }
        return state
    }

    private func saveState(_ state: GlucoseAlertState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    // MARK: Delivery

    private func fire(_ alert: GlucoseAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        // One pending notification per level: a fresh alert of the same level
        // updates rather than stacks.
        let request = UNNotificationRequest(
            identifier: "glucose-alert-\(alert.level.rawValue)",
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }
}
