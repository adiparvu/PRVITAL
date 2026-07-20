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
/// All three callbacks read `SharedStore.load()` (which falls back to
/// `GlucoseSnapshot.placeholder` when nothing has been published yet). The
/// timeline is a single entry for "now" with a 15-minute refresh window — the
/// app also nudges `WidgetCenter` whenever it saves a fresher snapshot, so this
/// interval is just a backstop.
struct GlucoseProvider: TimelineProvider {
    /// Minutes between backstop refreshes when the app is idle.
    private static let refreshMinutes = 10
    /// After this long with no fresh reading, the widget shows itself as stale.
    private static let staleAfterMinutes = 20.0

    func placeholder(in context: Context) -> GlucoseEntry {
        GlucoseEntry(date: Date(), snapshot: .placeholder)
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
