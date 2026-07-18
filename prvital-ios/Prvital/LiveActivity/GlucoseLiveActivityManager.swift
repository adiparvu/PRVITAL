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
    private var activity: Activity<GlucoseActivityAttributes>?

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
            isStale: snapshot.isStale
        )
        let content = ActivityContent(state: state, staleDate: snapshot.updatedAt.addingTimeInterval(30 * 60))

        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(attributes: GlucoseActivityAttributes(), content: content)
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    func sync(with snapshot: GlucoseSnapshot) {}
    func end() {}
    #endif
}
