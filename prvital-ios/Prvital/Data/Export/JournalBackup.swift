import Foundation
import SwiftData

/// The whole journal as one portable JSON document — every record family, with
/// ids, provenance and timestamps intact. This is the "all of it, mine" export:
/// insurance against a lost phone, a way to leave the app without losing a
/// single reading, and the file `restore` reads back.
///
/// Format notes: dates are ISO-8601 so the file is legible in any editor, and
/// the version field lets a future schema read old backups deliberately rather
/// than by accident.
struct JournalBackup: Codable, Sendable {
    static let currentVersion = 1

    var version = JournalBackup.currentVersion
    var exportedAt = Date()
    var glucose: [GlucoseRecord] = []
    var insulin: [InsulinRecord] = []
    var carbs: [CarbRecord] = []
    var activity: [ActivityRecord] = []
    var observations: [ObservationRecord] = []
    var medications: [MedicationRecord] = []
    var ketones: [KetoneRecord] = []

    var totalCount: Int {
        glucose.count + insulin.count + carbs.count + activity.count
            + observations.count + medications.count + ketones.count
    }

    struct GlucoseRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var valueMgdL: Double
        var sourceRaw: String
        var measurementTypeRaw: String
        var trendRaw: String?
        var isActive: Bool
    }

    struct InsulinRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var units: Double
        var insulinTypeRaw: String
        var insulinName: String?
        var deliveryMethodRaw: String
        var doseContextRaw: String
        var mealTagRaw: String?
        var note: String?
        var sourceRaw: String
    }

    struct CarbRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var grams: Double
        var mealTypeRaw: String
        var foodDescription: String?
        var note: String?
        var tagsRaw: [String]
        var sourceRaw: String
    }

    struct ActivityRecord: Codable, Sendable {
        var id: UUID
        var startTimestamp: Date
        var endTimestamp: Date?
        var durationSeconds: Int
        var activityTypeRaw: String
        var intensityRaw: String
        var caloriesBurned: Double?
        var distanceMeters: Double?
        var note: String?
        var sourceRaw: String
    }

    struct ObservationRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var tagsRaw: [String]
        var text: String?
        var sourceRaw: String
    }

    struct MedicationRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var name: String
        var kindRaw: String
        var amount: Double
        var unitText: String
        var note: String?
    }

    struct KetoneRecord: Codable, Sendable {
        var id: UUID
        var timestamp: Date
        var value: Double
        var sampleRaw: String
        var note: String?
    }
}

/// Builds and restores full-journal backups on a background ModelActor — a
/// long history is far too many rows for the main thread.
@ModelActor
actor JournalBackupStore {

    /// Every record in the store, as one encodable document.
    func makeBackup() -> JournalBackup {
        var backup = JournalBackup()
        backup.glucose = ((try? modelContext.fetch(FetchDescriptor<GlucoseReading>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, valueMgdL: $0.valueMgdL,
                  sourceRaw: $0.sourceRaw, measurementTypeRaw: $0.measurementTypeRaw,
                  trendRaw: $0.trendRaw, isActive: $0.isActive)
        }
        backup.insulin = ((try? modelContext.fetch(FetchDescriptor<InsulinDose>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, units: $0.units,
                  insulinTypeRaw: $0.insulinTypeRaw, insulinName: $0.insulinName,
                  deliveryMethodRaw: $0.deliveryMethodRaw, doseContextRaw: $0.doseContextRaw,
                  mealTagRaw: $0.mealTagRaw, note: $0.note, sourceRaw: $0.sourceRaw)
        }
        backup.carbs = ((try? modelContext.fetch(FetchDescriptor<CarbEntry>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, grams: $0.grams,
                  mealTypeRaw: $0.mealTypeRaw, foodDescription: $0.foodDescription,
                  note: $0.note, tagsRaw: $0.tagsRaw, sourceRaw: $0.sourceRaw)
        }
        backup.activity = ((try? modelContext.fetch(FetchDescriptor<ActivityEntry>())) ?? []).map {
            .init(id: $0.id, startTimestamp: $0.startTimestamp, endTimestamp: $0.endTimestamp,
                  durationSeconds: $0.durationSeconds, activityTypeRaw: $0.activityTypeRaw,
                  intensityRaw: $0.intensityRaw, caloriesBurned: $0.caloriesBurned,
                  distanceMeters: $0.distanceMeters, note: $0.note, sourceRaw: $0.sourceRaw)
        }
        backup.observations = ((try? modelContext.fetch(FetchDescriptor<ObservationEntry>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, tagsRaw: $0.tagsRaw,
                  text: $0.text, sourceRaw: $0.sourceRaw)
        }
        backup.medications = ((try? modelContext.fetch(FetchDescriptor<MedicationDose>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, name: $0.name, kindRaw: $0.kindRaw,
                  amount: $0.amount, unitText: $0.unitText, note: $0.note)
        }
        backup.ketones = ((try? modelContext.fetch(FetchDescriptor<KetoneReading>())) ?? []).map {
            .init(id: $0.id, timestamp: $0.timestamp, value: $0.value,
                  sampleRaw: $0.sampleRaw, note: $0.note)
        }
        return backup
    }

    /// Encodes the backup to a shareable file in the temporary directory.
    func writeBackupFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(makeBackup())

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "Prvital-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Inserts every record from the file that is not already in the store —
    /// matched by each record's own id, so restoring a backup on top of a live
    /// journal never duplicates and never overwrites an edit.
    func restore(from url: URL) throws -> Int {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(JournalBackup.self, from: Data(contentsOf: url))

        var inserted = 0
        let glucoseIDs = existingIDs(GlucoseReading.self, \.id)
        for r in backup.glucose where !glucoseIDs.contains(r.id) {
            let reading = GlucoseReading(
                id: r.id, valueMgdL: r.valueMgdL, timestamp: r.timestamp,
                source: DataSource(rawValue: r.sourceRaw) ?? .manual,
                measurementType: GlucoseMeasurementType(rawValue: r.measurementTypeRaw) ?? .manual,
                trend: r.trendRaw.flatMap(GlucoseTrend.init(rawValue:)))
            reading.isActive = r.isActive
            modelContext.insert(reading)
            inserted += 1
        }
        let insulinIDs = existingIDs(InsulinDose.self, \.id)
        for r in backup.insulin where !insulinIDs.contains(r.id) {
            let dose = InsulinDose(
                units: r.units, timestamp: r.timestamp,
                insulinType: InsulinType(rawValue: r.insulinTypeRaw) ?? .rapidActing,
                insulinName: r.insulinName,
                deliveryMethod: InsulinDeliveryMethod(rawValue: r.deliveryMethodRaw) ?? .pen,
                doseContext: InsulinDoseContext(rawValue: r.doseContextRaw) ?? .mealBolus,
                mealTag: r.mealTagRaw.flatMap(DoseMealTag.init(rawValue:)),
                note: r.note)
            dose.id = r.id
            dose.sourceRaw = r.sourceRaw
            modelContext.insert(dose)
            inserted += 1
        }
        let carbIDs = existingIDs(CarbEntry.self, \.id)
        for r in backup.carbs where !carbIDs.contains(r.id) {
            let entry = CarbEntry(
                grams: r.grams, timestamp: r.timestamp,
                mealType: MealType(rawValue: r.mealTypeRaw) ?? .lunch,
                foodDescription: r.foodDescription, note: r.note)
            entry.id = r.id
            entry.tagsRaw = r.tagsRaw
            entry.sourceRaw = r.sourceRaw
            modelContext.insert(entry)
            inserted += 1
        }
        let activityIDs = existingIDs(ActivityEntry.self, \.id)
        for r in backup.activity where !activityIDs.contains(r.id) {
            let entry = ActivityEntry(
                activityType: ActivityType(rawValue: r.activityTypeRaw) ?? .walking,
                startTimestamp: r.startTimestamp, durationSeconds: r.durationSeconds,
                intensity: ActivityIntensity(rawValue: r.intensityRaw) ?? .moderate,
                caloriesBurned: r.caloriesBurned, distanceMeters: r.distanceMeters,
                note: r.note)
            entry.id = r.id
            entry.endTimestamp = r.endTimestamp
            entry.sourceRaw = r.sourceRaw
            modelContext.insert(entry)
            inserted += 1
        }
        let observationIDs = existingIDs(ObservationEntry.self, \.id)
        for r in backup.observations where !observationIDs.contains(r.id) {
            let entry = ObservationEntry(
                tags: r.tagsRaw.compactMap(ObservationTag.init(rawValue:)),
                text: r.text, timestamp: r.timestamp)
            entry.id = r.id
            entry.sourceRaw = r.sourceRaw
            modelContext.insert(entry)
            inserted += 1
        }
        let medicationIDs = existingIDs(MedicationDose.self, \.id)
        for r in backup.medications where !medicationIDs.contains(r.id) {
            modelContext.insert(MedicationDose(
                id: r.id, name: r.name, kind: MedicationKind(rawValue: r.kindRaw) ?? .other,
                amount: r.amount, unitText: r.unitText, timestamp: r.timestamp, note: r.note))
            inserted += 1
        }
        let ketoneIDs = existingIDs(KetoneReading.self, \.id)
        for r in backup.ketones where !ketoneIDs.contains(r.id) {
            modelContext.insert(KetoneReading(
                id: r.id, value: r.value,
                sample: KetoneSample(rawValue: r.sampleRaw) ?? .blood,
                timestamp: r.timestamp, note: r.note))
            inserted += 1
        }

        try modelContext.save()
        return inserted
    }

    private func existingIDs<T: PersistentModel>(_ type: T.Type, _ keyPath: KeyPath<T, UUID>) -> Set<UUID> {
        let all = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        return Set(all.map { $0[keyPath: keyPath] })
    }
}
