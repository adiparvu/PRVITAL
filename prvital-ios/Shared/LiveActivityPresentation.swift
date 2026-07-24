import Foundation

/// Which of the Dynamic Island presentations the Live Activity is showing.
///
/// One Live Activity carries every state the design calls for — live glucose,
/// a logged action, a running countdown, or a critical alert — so the Island
/// never stacks duplicates and each state simply re-skins the same activity.
enum LiveActivityKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The live reading (stable / rising / falling / out-of-range).
    case glucose
    /// "Insulin logged — 4 units", with a confirmation bar.
    case insulinLogged
    /// "Meal logged — 45 g of carbs", with a confirmation bar.
    case mealLogged
    /// "Active insulin — 2h 45m", counting down to zero.
    case insulinOnBoard
    /// "Next meal in — 1h 15m", counting down.
    case mealCountdown
    /// Critical low.
    case alertLow
    /// Critical high.
    case alertHigh
    /// The CGM link came back.
    case sensorReconnected
    /// The transmitter battery is running out.
    case sensorBattery
}

/// The four headline states of a live glucose reading. Drives the colour, the
/// glyph and the headline of the `.glucose` presentation.
enum LiveGlucoseState: String, Codable, Hashable, Sendable, CaseIterable {
    case stable
    case rising
    case falling
    /// Out of the target band — the state that overrides any trend.
    case alert
}

/// The pure decision layer behind the Live Activity's look: which state a
/// reading is in, and which colour, glyph and headline that state wears.
///
/// Deliberately free of SwiftUI and of any store, so it is unit-testable and so
/// the widget process can render from plain values without the domain layer.
enum LiveActivityPresentation {

    // MARK: - Palette
    //
    // The Dynamic Island is always a dark surface, so these are the dark-mode
    // tones from `Theme` (no light variant needed). Kept as hex here — rather
    // than as `Color` — so the values cross the Codable activity payload and
    // stay testable without SwiftUI.

    /// In range and steady.
    static let stableHex: UInt = 0x34D07A
    /// Trending up.
    static let risingHex: UInt = 0xF7913D
    /// Trending down.
    static let fallingHex: UInt = 0x5AA9F8
    /// Out of range — the urgent state.
    static let alertHex: UInt = 0xF2626B
    /// Active insulin.
    static let insulinHex: UInt = 0xAF9BF5
    /// Carbohydrates.
    static let carbsHex: UInt = 0xF5C242
    /// A confirmed action / a healthy sensor link.
    static let confirmHex: UInt = 0x34D07A

    // MARK: - State

    /// The headline state of a reading.
    ///
    /// Out of range always wins: a value below `lower` or above `upper` reads as
    /// `.alert` no matter which way it is drifting, so a falling low can never
    /// present as a calm blue "falling". Inside the band the trend arrow decides.
    static func state(
        mgdL: Double,
        trendSymbol: String,
        targetLowerMgdL lower: Double,
        targetUpperMgdL upper: Double
    ) -> LiveGlucoseState {
        if mgdL < lower || mgdL > upper { return .alert }
        switch trendSymbol {
        case "arrow.up", "arrow.up.right": return .rising
        case "arrow.down", "arrow.down.right": return .falling
        default: return .stable
        }
    }

    // MARK: - Colour

    static func colorHex(for state: LiveGlucoseState) -> UInt {
        switch state {
        case .stable: stableHex
        case .rising: risingHex
        case .falling: fallingHex
        case .alert: alertHex
        }
    }

    /// The colour a whole presentation wears. For `.glucose` it follows the
    /// reading's state; every other kind has a fixed semantic colour.
    static func colorHex(for kind: LiveActivityKind, glucoseState: LiveGlucoseState) -> UInt {
        switch kind {
        case .glucose: colorHex(for: glucoseState)
        case .insulinLogged: confirmHex
        case .mealLogged: carbsHex
        case .insulinOnBoard: insulinHex
        case .mealCountdown: confirmHex
        case .alertLow, .alertHigh: alertHex
        case .sensorReconnected: confirmHex
        case .sensorBattery: carbsHex
        }
    }

    // MARK: - Glyph

    /// The SF Symbol shown at the leading edge of the compact pill.
    static func iconName(for kind: LiveActivityKind, glucoseState: LiveGlucoseState) -> String {
        switch kind {
        case .glucose:
            glucoseState == .alert ? "exclamationmark.triangle.fill" : "drop.fill"
        case .insulinLogged: "checkmark"
        case .mealLogged: "fork.knife"
        case .insulinOnBoard: "drop.halffull"
        case .mealCountdown: "applelogo"
        case .alertLow: "drop.fill"
        case .alertHigh: "arrow.up"
        case .sensorReconnected: "smallcircle.filled.circle"
        case .sensorBattery: "battery.25"
        }
    }

    // MARK: - Headline

    /// The headline under the pill for a live reading.
    static func headline(for state: LiveGlucoseState, isLow: Bool) -> String {
        switch state {
        case .stable: String(localized: "Glucose steady")
        case .rising: String(localized: "Glucose rising")
        case .falling: String(localized: "Glucose falling")
        case .alert:
            isLow ? String(localized: "Attention: Low") : String(localized: "Attention: High")
        }
    }

    /// The one-line reassurance under the headline for a live reading.
    static func caption(for state: LiveGlucoseState, isLow: Bool) -> String {
        switch state {
        case .stable: String(localized: "Everything is fine.")
        case .rising: String(localized: "Glucose is going up.")
        case .falling: String(localized: "Glucose is coming down.")
        case .alert:
            isLow
                ? String(localized: "Immediate attention needed!")
                : String(localized: "Check and correct.")
        }
    }

    // MARK: - Progress

    /// How far a countdown has run, as 0...1 — used for the accessibility value
    /// of the self-filling bar (the bar itself is driven by ActivityKit's timer).
    /// Returns nil when the window is empty or invalid.
    static func progressFraction(start: Date, end: Date, now: Date) -> Double? {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    // MARK: - Quick statistics
    //
    // The three figures of the expanded view's statistics row, computed over the
    // same recent window that feeds the chart. Pure so they are unit-testable and
    // so the widget process only ever receives the formatted result.

    /// Share of readings inside the target band, as 0...100. Nil when empty.
    static func timeInRangePercent(_ values: [Double], lower: Double, upper: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let inRange = values.filter { $0 >= lower && $0 <= upper }.count
        return Double(inRange) / Double(values.count) * 100
    }

    /// Mean of the readings. Nil when empty.
    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Population standard deviation of the readings. Nil with fewer than two.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mean = average(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
