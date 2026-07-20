import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the glucose **Live Activity** from the app, driven
/// entirely by the published `GlucoseSnapshot`: while there is a fresh reading
/// the activity is live and kept in sync; when the reading goes stale or absent
/// it ends. No user toggle needed — it follows the data.
@MainActor
final class GlucoseLiveActivityManager {
    static let shared = GlucoseLiveActivityManager()
    private init() {}

    #if canImport(ActivityKit) && os(iOS)
    private let store = LiveActivityStore()

    func sync(with snapshot: GlucoseSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let hasFreshReading = snapshot.updatedAt != .distantPast && !snapshot.isStale
        guard hasFreshReading else { end(); return }

        let state = GlucoseActivityAttributes.ContentState(
            mgdL: snapshot.mgdL,
            valueText: snapshot.valueText,
            unitText: snapshot.unitText,
            trendSymbol: snapshot.trendSymbol,
            trendLabel: snapshot.trendLabel,
            zoneLabel: snapshot.zoneLabel,
            zoneColorHex: snapshot.zoneColorHex,
            updatedAt: snapshot.updatedAt,
            isStale: snapshot.isStale,
            predictionText: snapshot.predictionText
        )
        let staleDate = snapshot.updatedAt.addingTimeInterval(30 * 60)
        let store = self.store
        Task { await store.upsert(state: state, staleDate: staleDate) }
    }

    func end() {
        let store = self.store
        Task { await store.finish() }
    }
    #else
    func sync(with snapshot: GlucoseSnapshot) {}
    func end() {}
    #endif
}

#if canImport(ActivityKit) && os(iOS)
/// Owns the Live Activity handle in a nonisolated, `@unchecked Sendable` box.
///
/// ActivityKit's `request`/`update`/`end` are `nonisolated async`; if the handle
/// were stored on an actor (including `@MainActor`), Swift 6 region isolation
/// rejects passing that actor-isolated value into those nonisolated calls
/// ("sending 'activity' risks causing data races"). Keeping it here — off any
/// actor — means the handle lives in a disconnected region, so the calls type
/// check. Every entry point is funneled from the main actor via
/// `GlucoseLiveActivityManager`, and the payloads passed in are `Sendable`, so
/// the single stored handle is effectively serialized in practice.
private final class LiveActivityStore: @unchecked Sendable {
    private var activity: Activity<GlucoseActivityAttributes>?

    func upsert(state: GlucoseActivityAttributes.ContentState, staleDate: Date) async {
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity {
            await activity.update(content)
        } else {
            activity = try? Activity.request(attributes: GlucoseActivityAttributes(), content: content)
        }
    }

    func finish() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }
}
#endif
