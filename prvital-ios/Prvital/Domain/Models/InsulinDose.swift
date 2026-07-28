import Foundation
import SwiftData

/// A single insulin administration (bolus or basal), in international units.
@Model
final class InsulinDose: MedicalRecord {
    /// Time index so windowed queries skip a full-table scan after a big import.
    #Index<InsulinDose>([\.timestamp])

    var id: UUID = UUID()
    var userID: String?
    var sourceRaw: String = DataSource.manual.rawValue
    var deviceID: String?
    var externalID: String?
    /// The CSV import batch this record came from, if any (for undo).
    var importBatchID: UUID?

    var timestamp: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Dose in international units (U).
    var units: Double = 0
    var insulinTypeRaw: String = InsulinType.rapidActing.rawValue
    var insulinName: String?
    var deliveryMethodRaw: String = InsulinDeliveryMethod.pen.rawValue
    var doseContextRaw: String = InsulinDoseContext.mealBolus.rawValue
    /// The user's explicit "for breakfast / lunch / dinner / snack" word, if
    /// given. Optional and defaulted so the addition is CloudKit-safe.
    var mealTagRaw: String?
    var note: String?

    /// When this manual entry was last mirrored into Apple Health — the
    /// timestamp its Health sample lives at, so edits and deletes can find and
    /// remove the old sample even after the entry's time changes.
    var healthKitSyncedAt: Date?

    var recordType: RecordType { .insulin }

    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var insulinType: InsulinType {
        get { InsulinType(rawValue: insulinTypeRaw) ?? .rapidActing }
        set { insulinTypeRaw = newValue.rawValue }
    }
    var deliveryMethod: InsulinDeliveryMethod {
        get { InsulinDeliveryMethod(rawValue: deliveryMethodRaw) ?? .pen }
        set { deliveryMethodRaw = newValue.rawValue }
    }
    var doseContext: InsulinDoseContext {
        get { InsulinDoseContext(rawValue: doseContextRaw) ?? .mealBolus }
        set { doseContextRaw = newValue.rawValue }
    }
    var mealTag: DoseMealTag? {
        get { mealTagRaw.flatMap(DoseMealTag.init(rawValue:)) }
        set { mealTagRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        units: Double,
        timestamp: Date = Date(),
        insulinType: InsulinType = .rapidActing,
        insulinName: String? = nil,
        deliveryMethod: InsulinDeliveryMethod = .pen,
        doseContext: InsulinDoseContext = .mealBolus,
        mealTag: DoseMealTag? = nil,
        source: DataSource = .manual,
        note: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.units = units
        self.timestamp = timestamp
        self.insulinTypeRaw = insulinType.rawValue
        self.insulinName = insulinName
        self.deliveryMethodRaw = deliveryMethod.rawValue
        self.doseContextRaw = doseContext.rawValue
        self.mealTagRaw = mealTag?.rawValue
        self.sourceRaw = source.rawValue
        self.note = note
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }
}
