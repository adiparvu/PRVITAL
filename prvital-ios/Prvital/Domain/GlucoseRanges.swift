import Foundation

/// User-configurable glucose thresholds, expressed in **mg/dL** internally.
///
/// Defaults follow the international consensus on Time in Range (ADA / ATTD):
/// a target range of 70–180 mg/dL, with 54 and 250 marking the "very low" and
/// "very high" boundaries. All comparisons in the app go through
/// `zone(forMgdL:)` so a single definition drives colours, statistics and alerts.
struct GlucoseThresholds: Codable, Equatable, Sendable {
    /// Below this is `.veryLow` (severe hypoglycaemia).
    var veryLow: Double = 54
    /// Lower bound of the target range. `.low` spans `veryLow ..< low`.
    var targetLower: Double = 70
    /// Upper bound of the target range (inclusive).
    var targetUpper: Double = 180
    /// Above this is `.veryHigh` (severe hyperglycaemia).
    var high: Double = 250

    static let standard = GlucoseThresholds()

    func zone(forMgdL value: Double) -> GlucoseZone {
        if value < veryLow { return .veryLow }
        if value < targetLower { return .low }
        if value <= targetUpper { return .inRange }
        if value <= high { return .high }
        return .veryHigh
    }

    /// True when a value falls inside the target range.
    func inRange(_ valueMgdL: Double) -> Bool {
        valueMgdL >= targetLower && valueMgdL <= targetUpper
    }
}

/// Formatting helpers so every screen renders values identically.
enum GlucoseFormatting {
    /// Formats a mg/dL value into the requested unit, e.g. "124" or "6.9".
    static func string(mgdL: Double, unit: GlucoseUnit) -> String {
        let converted = unit.fromMgdL(mgdL)
        return converted.formatted(
            .number.precision(.fractionLength(unit.fractionDigits))
        )
    }

    /// Value plus unit, e.g. "124 mg/dL".
    static func labeled(mgdL: Double, unit: GlucoseUnit) -> String {
        "\(string(mgdL: mgdL, unit: unit)) \(unit.rawValue)"
    }
}
