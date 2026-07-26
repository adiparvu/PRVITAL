import Foundation
import WidgetKit

/// A single point in the widget timeline: a wall-clock date plus the
/// display-ready `GlucoseSnapshot` to render at that moment.
struct GlucoseEntry: TimelineEntry {
    let date: Date
    let snapshot: GlucoseSnapshot
}

/// Feeds every glucose widget from the shared App Group snapshot.
///
/// Runtime callbacks read `SharedStore.load()`, which falls back to the honest
/// `.empty` ("—") snapshot — the realistic-looking `.placeholder` sample is
/// reserved for the widget-gallery preview, so a widget that can't load data
/// can never show a number that looks like a real reading. The app nudges
/// `WidgetCenter` whenever it saves a meaningfully fresher snapshot; the
/// timeline's own refresh policy is a low-frequency backstop chosen to stay
/// inside WidgetKit's ~40–70 reloads/day budget (a 10-minute backstop alone
/// would request 144/day and starve the widget — the "frozen widget" bug).
struct GlucoseProvider: TimelineProvider {
    /// Minutes between backstop refreshes when the app is idle.
    private static let refreshMinutes = 30
    /// After this long with no fresh reading, the widget shows itself as stale.
    private static let staleAfterMinutes = 20.0

    func placeholder(in context: Context) -> GlucoseEntry {
        // The redacted/loading shape. Uses the honest empty snapshot: if a widget
        // ever gets stuck here, it shows "—", not a plausible fake value.
        GlucoseEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        // The gallery preview should always show representative data, never a
        // possibly-empty real snapshot.
        let snapshot = context.isPreview ? GlucoseSnapshot.placeholder : SharedStore.load()
        completion(GlucoseEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        // WidgetKit's completion is not Sendable; the timeline is delivered
        // exactly once from the async work below, so the hand-off is safe.
        let box = CompletionBox(call: completion)
        Task {
            let now = Date()
            var snapshot = SharedStore.load()

            #if os(iOS)
            var refreshAfterMinutes = Self.refreshMinutes
            // When the app hasn't republished lately, fetch the newest reading
            // directly (shared-Keychain credentials) so the widget updates itself
            // even while iOS never wakes the app. Saved without a reload nudge —
            // this timeline is already being built. Adaptive next-reload: just
            // self-fetched → come back near the next CGM reading; could fetch but
            // nothing newer → moderate; no credentials → the low-frequency
            // backstop. iOS throttles to the daily budget either way, so these
            // are requests, not promises.
            if let refreshed = await WidgetSelfRefresh.refreshIfStale(snapshot, now: now) {
                SharedStore.save(refreshed, nudgeWidgets: false)
                snapshot = refreshed
                refreshAfterMinutes = 7
            } else if WidgetSelfRefresh.canFetch {
                refreshAfterMinutes = 15
            }
            #else
            let refreshAfterMinutes = Self.refreshMinutes
            #endif

            var entries = [GlucoseEntry(date: now, snapshot: snapshot)]

            // If there's a real, fresh reading, add a later entry that marks it stale
            // so the widget visibly dims once updates stop — even if the app can't run
            // to republish. The relative "updated" text keeps advancing on its own.
            if snapshot.updatedAt > .distantPast, !snapshot.isStale {
                let staleAt = max(
                    now.addingTimeInterval(60),
                    snapshot.updatedAt.addingTimeInterval(Self.staleAfterMinutes * 60)
                )
                var stale = snapshot
                stale.isStale = true
                entries.append(GlucoseEntry(date: staleAt, snapshot: stale))
            }

            let refreshDate = now.addingTimeInterval(Double(refreshAfterMinutes) * 60)
            box.call(Timeline(entries: entries, policy: .after(refreshDate)))
        }
    }
}

/// See `getTimeline` — carries WidgetKit's non-Sendable completion into the
/// one-shot async timeline build.
private struct CompletionBox: @unchecked Sendable {
    let call: (Timeline<GlucoseEntry>) -> Void
}
