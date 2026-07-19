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
    }

    var title: String = "Glucose"
}
#endif
