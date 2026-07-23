#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity attributes for the glucose Lock Screen / Dynamic Island. The
/// `ContentState` is a display-ready projection of `GlucoseSnapshot`, so the
/// widget process renders without any medical logic. Lives in `Shared/` so both
/// the app (which starts/updates) and the widget (which renders) see it.
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
    }

    var title: String = "Glucose"
}
#endif
