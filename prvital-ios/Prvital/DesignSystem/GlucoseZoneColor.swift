import SwiftUI

// Lives in the app target only (not shared into the widget/watch extensions,
// which don't compile the Domain layer). Maps a `GlucoseZone` to its dashboard
// indicator colour. The extensions render zone colour from
// `GlucoseSnapshot.zoneColorHex` via `Color(hex:)` instead.
extension GlucoseZone {
    /// The dashboard indicator colour for this zone (green / yellow / orange / red).
    var color: Color {
        switch self {
        case .veryLow: return Theme.zoneCritical
        case .low: return Theme.zoneWarning
        case .inRange: return Theme.zoneInRange
        case .high: return Theme.zoneHigh
        case .veryHigh: return Theme.zoneWarning
        }
    }
}
