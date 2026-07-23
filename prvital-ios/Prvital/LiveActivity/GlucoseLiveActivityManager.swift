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

        let outOfRange = snapshot.mgdL < snapshot.targetLowerMgdL
            || snapshot.mgdL > snapshot.targetUpperMgdL
        // The last handful of readings feed the expanded Dynamic Island sparkline.
        // Capped small so the activity's content payload stays well within budget.
        let recent = snapshot.points.suffix(16).map(\.mgdL)

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
            predictionText: snapshot.predictionText,
            iobText: snapshot.iobText,
            cobText: snapshot.cobText,
            targetLowerMgdL: snapshot.targetLowerMgdL,
            targetUpperMgdL: snapshot.targetUpperMgdL,
            isOutOfRange: outOfRange,
            recentMgdL: recent,
            forecastMgdL: snapshot.forecastMgdL
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

        // Re-adopt an activity started in a previous launch. The in-memory handle
        // is lost when the app is killed, but the Live Activity itself keeps
        // running — so without this we'd `request` a brand-new one on every
        // launch and they'd stack up on the Lock Screen (the "old one stays and a
        // new one appears" bug). Adopt the first existing activity and end any
        // extras a prior build may already have stacked.
        if activity == nil {
            let existing = Activity<GlucoseActivityAttributes>.activities
            activity = existing.first
            for extra in existing.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
        }

        if let activity {
            await activity.update(content)
        } else {
            activity = try? Activity.request(attributes: GlucoseActivityAttributes(), content: content)
        }
    }

    func finish() async {
        // End every running glucose activity, not just our handle, so any
        // duplicates left by an earlier build are cleared too.
        for a in Activity<GlucoseActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }
}
#endif
