import Foundation
import SwiftData

/// A carbohydrate intake, in grams, tied to a meal.
@Model
final class CarbEntry: MedicalRecord {
    /// Time index so windowed queries skip a full-table scan after a big import.
    #Index<CarbEntry>([\.timestamp])

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

    /// Carbohydrates in grams.
    var grams: Double = 0
    var mealTypeRaw: String = MealType.lunch.rawValue
    var foodDescription: String?
    var note: String?

    /// An optional photo of the meal. Held on disk via external storage rather
    /// than inline in the store, and kept out of the initialiser. Optional with a
    /// nil default keeps the schema CloudKit-safe; assign it after creation.
    @Attribute(.externalStorage) var photo: Data?

    /// Quick context tags (eating out, alcohol, travel…), raw-stored like the
    /// observation's. Defaulted so the addition is CloudKit-safe.
    var tagsRaw: [String] = []

    /// When this manual entry was last mirrored into Apple Health — the
    /// timestamp its Health sample lives at, so edits and deletes can find and
    /// remove the old sample even after the entry's time changes.
    var healthKitSyncedAt: Date?

    var recordType: RecordType { .carbohydrate }

    var tags: [ObservationTag] {
        get { tagsRaw.compactMap(ObservationTag.init(rawValue:)) }
        set { tagsRaw = newValue.map(\.rawValue) }
    }

    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        grams: Double,
        timestamp: Date = Date(),
        mealType: MealType = .lunch,
        foodDescription: String? = nil,
        source: DataSource = .manual,
        note: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.grams = grams
        self.timestamp = timestamp
        self.mealTypeRaw = mealType.rawValue
        self.foodDescription = foodDescription
        self.sourceRaw = source.rawValue
        self.note = note
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }
}
