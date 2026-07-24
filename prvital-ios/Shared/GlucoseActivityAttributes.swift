#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity attributes for the glucose Lock Screen / Dynamic Island. The
/// `ContentState` is a display-ready projection of `GlucoseSnapshot`, so the
/// widget process renders without any medical logic. Lives in `Shared/` so both
/// the app (which starts/updates) and the widget (which renders) see it.
///
/// A single activity carries **every** Dynamic Island presentation — the live
/// reading, a logged action, a running countdown, a critical alert — selected by
/// `kind`. One activity re-skinned means the Island never stacks duplicates and
/// a state change is an `update`, not a new request.
struct GlucoseActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var mgdL: Double
        var valueText: String
        var unitText: String
        var trendSymbol: String
        var trendLabel: String
        var zoneLabel: String
        var zoneColorHex: UInt
        var updatedAt: Date
        var isStale: Bool
        var predictionText: String?
        /// Insulin- and carbs-on-board, pre-formatted (e.g. "1.2 U", "45 g").
        var iobText: String?
        var cobText: String?

        // Extra context the Dynamic Island uses for its live mini-chart and its
        // out-of-range pulse. The Lock Screen banner ignores these.
        var targetLowerMgdL: Double = 70
        var targetUpperMgdL: Double = 180
        /// True when the current reading is outside the target band — drives the
        /// discrete pulse animation in the Dynamic Island.
        var isOutOfRange: Bool = false
        /// The recent readings (oldest → newest, mg/dL) for the expanded Dynamic
        /// Island sparkline. Capped small so the activity payload stays tiny.
        var recentMgdL: [Double] = []
        /// A short-horizon projected value drawn as a dashed continuation past the
        /// last reading on the sparkline. Nil when there's no moving projection.
        var forecastMgdL: Double? = nil
        /// When the next CGM sample is expected (last reading + the measured
        /// sensor cadence). Lets the Live Activity fill a progress bar toward it on
        /// its own — one of the few things ActivityKit animates between data
        /// pushes. Nil when the cadence is unknown or on decoded older activities.
        var nextReadingAt: Date? = nil

        // MARK: - Presentation

        /// Which presentation to render. Defaults to the live reading so an
        /// activity decoded from an older build still shows something sensible.
        var kind: LiveActivityKind = .glucose
        /// The headline state of the reading, precomputed by the app so the widget
        /// process never re-derives medical meaning.
        var glucoseState: LiveGlucoseState = .stable
        /// The presentation's colour (0xRRGGBB) and leading glyph, both resolved by
        /// `LiveActivityPresentation` in the app.
        var stateColorHex: UInt = LiveActivityPresentation.stableHex
        var iconName: String = "drop.fill"

        // MARK: - Event payload
        //
        // Pre-formatted strings for the action / countdown / alert presentations,
        // so the extension renders text it never has to compute.

        /// The short value inside the compact pill — "4U", "45g", "2:45", "20%".
        var eventCompactText: String? = nil
        /// The headline of the expanded / Lock Screen card — "Insulin logged".
        var eventTitle: String? = nil
        /// The prominent line under it — "4 units", "Low: 2.8 mmol/L".
        var eventDetail: String? = nil
        /// The quiet line under that — "Have 15 g of carbs".
        var eventCaption: String? = nil

        /// The window a self-filling bar runs over: a confirmation sweep for a
        /// logged action, or the countdown for active insulin / the next meal.
        var progressStart: Date? = nil
        var progressEnd: Date? = nil

        // MARK: - Quick stats (expanded glucose view)

        /// Pre-formatted "78%", "6.7", "±1.2" for the expanded statistics row.
        var tirText: String? = nil
        var averageText: String? = nil
        var deviationText: String? = nil

        /// Pre-formatted axis ticks for the expanded chart — three y labels
        /// (high → low) and up to four x labels (oldest → "Now"). Composed in the
        /// app so the widget never converts units or formats dates itself.
        var chartYLabels: [String] = []
        var chartXLabels: [String] = []
    }

    var title: String = "Glucose"
}
#endif
