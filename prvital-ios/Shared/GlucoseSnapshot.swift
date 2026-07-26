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
    var trendLabel: String = String(localized: "Stable")
    var zoneLabel: String = String(localized: "In range")
    /// Zone colour as 0xRRGGBB so the extension can render without the palette.
    var zoneColorHex: UInt = 0x2FB86B
    var sourceName: String = "—"
    /// The `DataSource` raw value behind `sourceName`, so the widget's
    /// self-refresh knows which credentialed service to ask first. Optional and
    /// additive — old snapshots decode with nil.
    var sourceRaw: String?
    var updatedAt: Date = .distantPast
    var isStale: Bool = true

    var points: [Point] = []
    var targetLowerMgdL: Double = 70
    var targetUpperMgdL: Double = 180

    /// A short-horizon projected reading, so a chart can draw the trajectory as a
    /// dashed segment continuing past the last real point. Both are nil unless the
    /// app has a fresh reading with a measured trend and the projected change is big
    /// enough to be worth showing — see `SnapshotPublisher`.
    var forecastMgdL: Double?
    /// When the projected reading lands (last reading time + horizon).
    var forecastAt: Date?
    /// The honest plausible range around `forecastMgdL` (from `GlucoseForecast`), so
    /// a chart can fan a faint uncertainty cone out to the horizon. Nil when there's
    /// no forecast.
    var forecastLowMgdL: Double?
    var forecastHighMgdL: Double?

    /// Today's headline figures, pre-formatted by the app ("74%", "128"), so the
    /// large/extra-large widgets can show a stats row without running any
    /// medical math in the widget process. Nil until today has readings.
    var todayTIRText: String?
    var todayAverageText: String?

    var lastInsulinText: String?
    var lastMealText: String?
    var nextReminderText: String?
    /// A localized "Low/High predicted in ~N min" when a low or high is imminent.
    var predictionText: String?
    /// Insulin- and carbs-on-board, pre-formatted (e.g. "1.2 U", "45 g"), for the
    /// Live Activity / Dynamic Island. Nil when there's none (or the calculator is off).
    var iobText: String?
    var cobText: String?
    var recentEntries: [String] = []

    /// The honest "no data" state: an em-dash, neutral grey, already stale. This is
    /// what widgets render when no snapshot has ever been published or the shared
    /// store can't be read. It must be visibly *not a reading* — a frozen widget
    /// showing a realistic-looking number is dangerous in a glucose app.
    static let empty = GlucoseSnapshot(
        valueText: "—", unitText: "mg/dL", mgdL: 0,
        trendSymbol: "minus", trendLabel: String(localized: "No data"),
        zoneLabel: String(localized: "No data"), zoneColorHex: 0x8E8E93,
        sourceName: "—", updatedAt: .distantPast, isStale: true
    )

    /// Rich sample data for the widget-gallery preview ONLY (`context.isPreview`).
    /// Never use this as a runtime fallback: it looks exactly like a real reading.
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
