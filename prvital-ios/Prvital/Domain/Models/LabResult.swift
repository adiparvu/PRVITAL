import Foundation
import SwiftData

/// A real clinic **HbA1c** result the user copies in from a lab report.
///
/// Prvital already estimates A1c from the CGM trace (the Glucose Management
/// Indicator). Recording the true, lab-measured value lets the app overlay the
/// two so the user — and their care team — can see how closely the sensor
/// estimate tracks the gold-standard blood test, and spot any consistent gap.
///
/// CloudKit-safe by construction: every stored property has a default, the note
/// is optional to stand in for an absent value, and there are no unique
/// constraints — so SwiftData can mirror it to the user's private CloudKit
/// database.
@Model
final class LabResult {
    var id: UUID = UUID()
    /// The lab HbA1c as a percentage (e.g. `6.8` for 6.8 %).
    var value: Double = 0
    /// When the blood was drawn / the result is dated.
    var timestamp: Date = Date()
    /// A free-text note (clinic, fasting, anything the user wants on hand).
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        value: Double = 0,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.value = value
        self.timestamp = timestamp
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
