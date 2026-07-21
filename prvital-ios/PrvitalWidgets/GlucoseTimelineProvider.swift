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
        let now = Date()
        let snapshot = SharedStore.load()
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

        let refreshDate = now.addingTimeInterval(Double(Self.refreshMinutes) * 60)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}
