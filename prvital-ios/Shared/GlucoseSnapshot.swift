import Foundation

/// A display-ready snapshot the app publishes to the shared App Group for the
/// widgets and the watch. It is deliberately **self-contained** — only
/// primitives and pre-formatted strings — so the extensions never need the
/// domain layer and no medical logic runs in the widget process.
struct GlucoseSnapshot: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable, Identifiable {
        var date: Date
        var mgdL: Double
        var id: Date { date }
    }

    var valueText: String = "—"
    var unitText: String = "mg/dL"
    var mgdL: Double = 0
    var trendSymbol: String = "arrow.right"
    var trendLabel: String = "Stable"
    var zoneLabel: String = "In range"
    /// Zone colour as 0xRRGGBB so the extension can render without the palette.
    var zoneColorHex: UInt = 0x2FB86B
    var sourceName: String = "—"
    var updatedAt: Date = .distantPast
    var isStale: Bool = true

    var points: [Point] = []
    var targetLowerMgdL: Double = 70
    var targetUpperMgdL: Double = 180

    var lastInsulinText: String?
    var lastMealText: String?
    var nextReminderText: String?
    var recentEntries: [String] = []

    static let placeholder = GlucoseSnapshot(
        valueText: "124", unitText: "mg/dL", mgdL: 124,
        trendSymbol: "arrow.right", trendLabel: "Stable",
        zoneLabel: "In range", zoneColorHex: 0x2FB86B,
        sourceName: "Dexcom", updatedAt: Date(), isStale: false,
        points: (0..<12).map { Point(date: Date().addingTimeInterval(Double($0 - 12) * 900), mgdL: 110 + Double($0 % 5) * 8) },
        lastInsulinText: "4 U · 1h ago",
        lastMealText: "45 g · Lunch",
        nextReminderText: "Basal at 22:00",
        recentEntries: ["124 mg/dL · now", "4 U rapid · 1h ago", "45 g lunch · 1h ago"]
    )
}
