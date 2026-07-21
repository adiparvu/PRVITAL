import Foundation

/// Classifies a blood-ketone value (mmol/L) into the widely-taught risk bands,
/// with supportive, non-prescriptive guidance. Pure and deterministic.
///
/// Bands follow common clinical education for blood ketones:
///   < 0.6      normal
///   0.6 – 1.5  slightly raised — recheck, follow your sick-day plan
///   1.5 – 3.0  raised — risk of DKA, contact your care team
///   > 3.0      high — seek urgent medical care
///
/// This is general education, never a diagnosis or a dose.
enum KetoneBand: String, Sendable, CaseIterable {
    case normal
    case elevated
    case high
    case veryHigh

    var title: String {
        switch self {
        case .normal: return String(localized: "Normal")
        case .elevated: return String(localized: "Slightly raised")
        case .high: return String(localized: "Raised")
        case .veryHigh: return String(localized: "High")
        }
    }

    /// Supportive guidance for the band. Always points to the care team for
    /// anything beyond monitoring.
    var guidance: String {
        switch self {
        case .normal:
            return String(localized: "Ketones are in the normal range. Keep hydrated and carry on with your usual routine.")
        case .elevated:
            return String(localized: "Slightly raised. Drink water, recheck in a couple of hours, and follow your sick-day plan. Keep taking insulin.")
        case .high:
            return String(localized: "Raised — this carries a risk of DKA. Contact your care team and follow your ketone plan now.")
        case .veryHigh:
            return String(localized: "High ketones. Seek urgent medical care, especially with vomiting, belly pain, or trouble breathing.")
        }
    }

    /// A traffic-light severity for tinting (0 calm → 3 urgent).
    var severity: Int {
        switch self {
        case .normal: return 0
        case .elevated: return 1
        case .high: return 2
        case .veryHigh: return 3
        }
    }
}

enum KetoneBands {
    static let elevatedThreshold = 0.6
    static let highThreshold = 1.5
    static let veryHighThreshold = 3.0

    static func band(forMmolPerL value: Double) -> KetoneBand {
        if value >= veryHighThreshold { return .veryHigh }
        if value >= highThreshold { return .high }
        if value >= elevatedThreshold { return .elevated }
        return .normal
    }
}
