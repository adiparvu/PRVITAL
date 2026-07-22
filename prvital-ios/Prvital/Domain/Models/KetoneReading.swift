import Foundation
import SwiftData

/// A blood (or urine) **ketone** measurement the user records, especially while
/// unwell or when glucose runs high. Ketones are the early-warning sign for
/// diabetic ketoacidosis, so having them logged next to glucose matters.
///
/// Values are stored in **mmol/L** (the blood-ketone standard). CloudKit-safe by
/// construction: every stored property has a default, the note is optional, and
/// there are no unique constraints.
@Model
final class KetoneReading {
    /// Time index so windowed queries skip a full-table scan after a big import.
    #Index<KetoneReading>([\.timestamp])

    var id: UUID = UUID()
    /// Blood ketone concentration in mmol/L (e.g. `0.4`, `1.8`).
    var value: Double = 0
    var timestamp: Date = Date()
    /// How it was measured, stored raw for CloudKit-friendly persistence.
    var sampleRaw: String = KetoneSample.blood.rawValue
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var sample: KetoneSample {
        get { KetoneSample(rawValue: sampleRaw) ?? .blood }
        set { sampleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        value: Double = 0,
        sample: KetoneSample = .blood,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.value = value
        self.sampleRaw = sample.rawValue
        self.timestamp = timestamp
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Where a ketone measurement came from.
enum KetoneSample: String, Codable, CaseIterable, Sendable, Identifiable {
    case blood
    case urine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blood: return String(localized: "Blood")
        case .urine: return String(localized: "Urine")
        }
    }
}
