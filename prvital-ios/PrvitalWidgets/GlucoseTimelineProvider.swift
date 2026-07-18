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
    private static let refreshMinutes = 15

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
        let entry = GlucoseEntry(date: now, snapshot: SharedStore.load())
        let refreshDate = Calendar.current.date(
            byAdding: .minute,
            value: Self.refreshMinutes,
            to: now
        ) ?? now.addingTimeInterval(Double(Self.refreshMinutes) * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}
