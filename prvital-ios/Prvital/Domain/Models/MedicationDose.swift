import Foundation
import SwiftData

/// A broad category for a non-insulin medication, used for the icon and grouping.
enum MedicationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case metformin
    case glp1          // GLP-1 receptor agonists (semaglutide, etc.)
    case sglt2         // SGLT2 inhibitors
    case dpp4          // DPP-4 inhibitors
    case sulfonylurea
    case bloodPressure
    case statin
    case supplement
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metformin: return String(localized: "Metformin")
        case .glp1: return String(localized: "GLP-1")
        case .sglt2: return String(localized: "SGLT2 inhibitor")
        case .dpp4: return String(localized: "DPP-4 inhibitor")
        case .sulfonylurea: return String(localized: "Sulfonylurea")
        case .bloodPressure: return String(localized: "Blood pressure")
        case .statin: return String(localized: "Statin")
        case .supplement: return String(localized: "Supplement")
        case .other: return String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .metformin, .sulfonylurea, .dpp4: return "pills.fill"
        case .glp1: return "syringe"
        case .sglt2: return "drop.fill"
        case .bloodPressure: return "heart.fill"
        case .statin: return "bolt.heart.fill"
        case .supplement: return "leaf.fill"
        case .other: return "cross.case.fill"
        }
    }
}

/// A logged dose of a **non-insulin** medication (insulin has its own model). A
/// `MedicalRecord`, so it flows through the journal, audit and export like every
/// other entry. Every stored property has a default and there are no unique
/// constraints, so the type is CloudKit-safe.
@Model
final class MedicationDose: MedicalRecord {
    var id: UUID = UUID()
    var userID: String?
    var sourceRaw: String = DataSource.manual.rawValue
    var deviceID: String?
    var externalID: String?

    var timestamp: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var name: String = ""
    var kindRaw: String = MedicationKind.other.rawValue
    var amount: Double = 0
    var unitText: String = ""
    /// The planned-slot id this dose fulfilled, when logged from the schedule.
    var scheduleID: String?
    var note: String?

    var recordType: RecordType { .medication }

    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// A display string like "500 mg" or "1 tablet"; falls back to just the name.
    var doseText: String {
        guard amount > 0, !unitText.isEmpty else { return name }
        let n = amount.formatted(.number.precision(.fractionLength(amount == amount.rounded() ? 0 : 2)))
        return "\(n) \(unitText)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: MedicationKind = .other,
        amount: Double = 0,
        unitText: String = "",
        timestamp: Date = Date(),
        scheduleID: String? = nil,
        source: DataSource = .manual,
        note: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.unitText = unitText
        self.timestamp = timestamp
        self.scheduleID = scheduleID
        self.sourceRaw = source.rawValue
        self.note = note
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }
}
