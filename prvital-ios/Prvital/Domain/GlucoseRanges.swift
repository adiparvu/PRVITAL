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

    // MARK: Night target range
    //
    // An optional, tighter target for sleeping hours (many people aim lower and
    // steadier overnight). All-additive with safe defaults so an old stored value
    // decodes unchanged and, while `nightModeEnabled` is false, every method below
    // behaves exactly as before.

    /// When true, the night bounds apply during the night window.
    var nightModeEnabled: Bool = false
    /// Lower/upper target during the night window (defaults: 80–180).
    var nightTargetLower: Double = 80
    var nightTargetUpper: Double = 180
    /// Night window as minutes from midnight; wraps midnight when start > end
    /// (the default 22:00 → 06:00 does).
    var nightStartMinute: Int = 22 * 60
    var nightEndMinute: Int = 6 * 60

    static let standard = GlucoseThresholds()

    // Memberwise init stays synthesized (used by `.standard` and callers). A
    // tolerant decoder is spelled out so data saved before the night fields
    // existed still decodes — otherwise the missing keys would throw and a
    // user's custom day range would silently reset to the defaults on update.
    private enum CodingKeys: String, CodingKey {
        case veryLow, targetLower, targetUpper, high
        case nightModeEnabled, nightTargetLower, nightTargetUpper, nightStartMinute, nightEndMinute
    }

    init(veryLow: Double = 54, targetLower: Double = 70, targetUpper: Double = 180, high: Double = 250,
         nightModeEnabled: Bool = false, nightTargetLower: Double = 80, nightTargetUpper: Double = 180,
         nightStartMinute: Int = 22 * 60, nightEndMinute: Int = 6 * 60) {
        self.veryLow = veryLow
        self.targetLower = targetLower
        self.targetUpper = targetUpper
        self.high = high
        self.nightModeEnabled = nightModeEnabled
        self.nightTargetLower = nightTargetLower
        self.nightTargetUpper = nightTargetUpper
        self.nightStartMinute = nightStartMinute
        self.nightEndMinute = nightEndMinute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        veryLow = try c.decodeIfPresent(Double.self, forKey: .veryLow) ?? 54
        targetLower = try c.decodeIfPresent(Double.self, forKey: .targetLower) ?? 70
        targetUpper = try c.decodeIfPresent(Double.self, forKey: .targetUpper) ?? 180
        high = try c.decodeIfPresent(Double.self, forKey: .high) ?? 250
        nightModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .nightModeEnabled) ?? false
        nightTargetLower = try c.decodeIfPresent(Double.self, forKey: .nightTargetLower) ?? 80
        nightTargetUpper = try c.decodeIfPresent(Double.self, forKey: .nightTargetUpper) ?? 180
        nightStartMinute = try c.decodeIfPresent(Int.self, forKey: .nightStartMinute) ?? (22 * 60)
        nightEndMinute = try c.decodeIfPresent(Int.self, forKey: .nightEndMinute) ?? (6 * 60)
    }

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

    // MARK: Time-aware variants

    /// True when `date`'s local time falls in the night window. Always false when
    /// night mode is off.
    func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard nightModeEnabled else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if nightStartMinute <= nightEndMinute {
            return minute >= nightStartMinute && minute < nightEndMinute
        }
        return minute >= nightStartMinute || minute < nightEndMinute
    }

    /// The lower/upper target effective at `date` (night bounds during night).
    func targetLower(at date: Date, calendar: Calendar = .current) -> Double {
        isNight(date, calendar: calendar) ? nightTargetLower : targetLower
    }
    func targetUpper(at date: Date, calendar: Calendar = .current) -> Double {
        isNight(date, calendar: calendar) ? nightTargetUpper : targetUpper
    }

    /// The zone at a value, honouring the night band when night mode is on.
    func zone(forMgdL value: Double, at date: Date, calendar: Calendar = .current) -> GlucoseZone {
        guard nightModeEnabled else { return zone(forMgdL: value) }
        let lower = targetLower(at: date, calendar: calendar)
        let upper = targetUpper(at: date, calendar: calendar)
        if value < veryLow { return .veryLow }
        if value < lower { return .low }
        if value <= upper { return .inRange }
        if value <= high { return .high }
        return .veryHigh
    }

    /// Time-aware in-range check.
    func inRange(_ valueMgdL: Double, at date: Date, calendar: Calendar = .current) -> Bool {
        valueMgdL >= targetLower(at: date, calendar: calendar)
            && valueMgdL <= targetUpper(at: date, calendar: calendar)
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
