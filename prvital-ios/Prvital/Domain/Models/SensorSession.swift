import Foundation
import SwiftData

/// A continuous-glucose-sensor wear session the user started. Because Dexcom
/// Share and similar feeds don't expose the true session start, the user marks
/// when they insert a sensor and Prvital tracks the warm-up and expiry countdown.
///
/// CloudKit-safe: every stored property has a default and there are no unique
/// constraints.
@Model
final class SensorSession {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var kindRaw: String = SensorKind.dexcomG7.rawValue
    var createdAt: Date = Date()

    var kind: SensorKind {
        get { SensorKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// When the sensor is due to be replaced.
    var expiryDate: Date { startDate.addingTimeInterval(kind.lifetime) }

    init(id: UUID = UUID(), startDate: Date = Date(), kind: SensorKind = .dexcomG7, createdAt: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }
}
