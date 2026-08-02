import Foundation
import SwiftData

/// The whole journal as one portable JSON document — every record family, with
/// ids, provenance and timestamps intact, plus the things that make the journal
/// *yours*: favorite meals, lab results, sensor sessions, the profile and the
/// app's settings. This is the "all of it, mine" export: insurance against a
/// lost phone, a way to leave the app without losing a single reading, and the
/// file `restore` reads back.
///
/// Format notes: dates are ISO-8601 so the file is legible in any editor, and
/// the version field lets a future schema read old backups deliberately rather
/// than by accident. Version 1 files (records only) restore cleanly: every
/// added field decodes as absent-with-default.
struct JournalBackup: Codable, Sendable {
    static let currentVersion = 2

    var version = JournalBackup.currentVersion
    var exportedAt = Date()
    var glucose: [GlucoseRecord] = []
    var insulin: [InsulinRecord] = []
    var carbs: [CarbRecord] = []
    var activity: [ActivityRecord] = []
    var observations: [ObservationRecord] = []
    var medications: [MedicationRecord] = []
    var ketones: [KetoneRecord] = []
    var favorites: [FavoriteRecord] = []
    var labResults: [LabRecord] = []
    var sensorSessions: [SensorRecord] = []
    var profile: ProfileRecord?
    var settings: [String: SettingValue] = [:]

    var totalCount: Int {
        glucose.count + insulin.count + carbs.count + activity.count
            + observations.count + medications.count + ketones.count
            + favorites.count + labResults.count + sensorSessions.count
    }

    init() {}

    // Tolerant decoding: a version-1 file has none of the newer keys, and a
    // future version may carry keys this build doesn't know — both must decode
    // without a throw. Encoding stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, glucose, insulin, carbs, activity
        case observations, medications, ketones
        case favorites, labResults, sensorSessions, profile, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        glucose = try c.decodeIfPresent([GlucoseRecord].self, forKey: .glucose) ?? []
        insulin = try c.decodeIfPresent([InsulinRecord].self, forKey: .insulin) ?? []
        carbs = try c.decodeIfPresent([CarbRecord].self, forKey: .carbs) ?? []
        activity = try c.decodeIfPresent([ActivityRecord].self, forKey: .activity) ?? []
        observations = try c.decodeIfPresent([ObservationRecord].self, forKey: .observations) ?? []
        medications = try c.decodeIfPresent([MedicationRecord].self, forKey: .medications) ?? []
        ketones = try c.decodeIfPresent([KetoneRecord].self, forKey: .ketones) ?? []
        favorites = try c.decodeIfPresent([FavoriteRecord].self, forKey: .favorites) ?? []
        labResults = try c.decodeIfPresent([LabRecord].self, forKey: .labResults) ?? []
        sensorSessions = try c.decodeIfPresent([SensorRecord].self, forKey: .sensorSessions) ?? []
        profile = try c.decodeIfPresent(ProfileRecord.self, forKey: .profile)
        settings = try c.decodeIfPresent([String: SettingValue].self, forKey: .settings) ?? [:]
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

    struct FavoriteRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var grams: Double
        var mealTypeRaw: String
        var foodDescription: String?
        var usualMinutesFromMidnight: Int?
        var timesUsed: Int
        var lastUsedAt: Date?
        var createdAt: Date
    }

    struct LabRecord: Codable, Sendable {
        var id: UUID
        var value: Double
        var timestamp: Date
        var note: String?
    }

    struct SensorRecord: Codable, Sendable {
        var id: UUID
        var startDate: Date
        var kindRaw: String
        var createdAt: Date
    }

    struct ProfileRecord: Codable, Sendable {
        var id: UUID
        var displayName: String
        var avatarSymbol: String
        var diabetesTypeRaw: String
        var therapyRaw: String
        var diagnosisYear: Int?
        var careTeamNote: String?
        var avatarColorHex: String?
        var avatarImageData: Data?
        var birthYear: Int?
        var weightKg: Double?
        var heightCm: Double?
        var basalInsulinName: String?
        var bolusInsulinName: String?
        var cgmModel: String?
        var meterModel: String?
        var pumpModel: String?
        var doctorName: String?
        var doctorPhone: String?
        var nextAppointment: Date?
    }

    /// One preference value, preserving its stored type so a restore writes the
    /// same plist shape the app reads back. Unknown shapes are simply skipped.
    enum SettingValue: Codable, Sendable, Equatable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case stringArray([String])
        case data(Data)
        case date(Date)
        case dateDict([String: Date])

        /// Wraps a value read from `UserDefaults`, or nil for unsupported types.
        /// Booleans hide inside `NSNumber`, so the CF type check keeps a stored
        /// `true` from coming back as the integer 1.
        init?(any value: Any) {
            switch value {
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else if CFNumberIsFloatType(number) {
                    self = .double(number.doubleValue)
                } else {
                    self = .int(number.intValue)
                }
            case let text as String: self = .string(text)
            case let blob as Data: self = .data(blob)
            case let stamp as Date: self = .date(stamp)
            case let list as [String]: self = .stringArray(list)
            case let map as [String: Date]: self = .dateDict(map)
            default: return nil
            }
        }

        /// The value in the shape `UserDefaults.set(_:forKey:)` accepts.
        var plistValue: Any {
            switch self {
            case .bool(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            case .string(let v): return v
            case .stringArray(let v): return v
            case .data(let v): return v
            case .date(let v): return v
            case .dateDict(let v): return v
            }
        }

        private enum CodingKeys: String, CodingKey {
            case bool, int, double, string, stringArray, data, date, dateDict
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let v = try c.decodeIfPresent(Bool.self, forKey: .bool) { self = .bool(v) }
            else if let v = try c.decodeIfPresent(Int.self, forKey: .int) { self = .int(v) }
            else if let v = try c.decodeIfPresent(Double.self, forKey: .double) { self = .double(v) }
            else if let v = try c.decodeIfPresent(String.self, forKey: .string) { self = .string(v) }
            else if let v = try c.decodeIfPresent([String].self, forKey: .stringArray) { self = .stringArray(v) }
            else if let v = try c.decodeIfPresent(Data.self, forKey: .data) { self = .data(v) }
            else if let v = try c.decodeIfPresent(Date.self, forKey: .date) { self = .date(v) }
            else if let v = try c.decodeIfPresent([String: Date].self, forKey: .dateDict) { self = .dateDict(v) }
            else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "No recognised setting value"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bool(let v): try c.encode(v, forKey: .bool)
            case .int(let v): try c.encode(v, forKey: .int)
            case .double(let v): try c.encode(v, forKey: .double)
            case .string(let v): try c.encode(v, forKey: .string)
            case .stringArray(let v): try c.encode(v, forKey: .stringArray)
            case .data(let v): try c.encode(v, forKey: .data)
            case .date(let v): try c.encode(v, forKey: .date)
            case .dateDict(let v): try c.encode(v, forKey: .dateDict)
            }
        }
    }
}

/// Builds and restores full-journal backups on a background ModelActor — a
/// long history is far too many rows for the main thread.
@ModelActor
actor JournalBackupStore {

    /// The two settings that live in the STANDARD defaults rather than the App
    /// Group suite (injection-site rotation and the auto-backup switch itself).
    private static let standardDefaultsKeys = [
        "injectionSites.lastUsed", "backup.autoWeeklyEnabled",
    ]

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
        backup.favorites = ((try? modelContext.fetch(FetchDescriptor<FavoriteMeal>())) ?? []).map {
            .init(id: $0.id, name: $0.name, grams: $0.grams, mealTypeRaw: $0.mealTypeRaw,
                  foodDescription: $0.foodDescription,
                  usualMinutesFromMidnight: $0.usualMinutesFromMidnight,
                  timesUsed: $0.timesUsed, lastUsedAt: $0.lastUsedAt, createdAt: $0.createdAt)
        }
        backup.labResults = ((try? modelContext.fetch(FetchDescriptor<LabResult>())) ?? []).map {
            .init(id: $0.id, value: $0.value, timestamp: $0.timestamp, note: $0.note)
        }
        backup.sensorSessions = ((try? modelContext.fetch(FetchDescriptor<SensorSession>())) ?? []).map {
            .init(id: $0.id, startDate: $0.startDate, kindRaw: $0.kindRaw, createdAt: $0.createdAt)
        }
        if let p = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first {
            backup.profile = .init(
                id: p.id, displayName: p.displayName, avatarSymbol: p.avatarSymbol,
                diabetesTypeRaw: p.diabetesTypeRaw, therapyRaw: p.therapyRaw,
                diagnosisYear: p.diagnosisYear, careTeamNote: p.careTeamNote,
                avatarColorHex: p.avatarColorHex, avatarImageData: p.avatarImageData,
                birthYear: p.birthYear, weightKg: p.weightKg, heightCm: p.heightCm,
                basalInsulinName: p.basalInsulinName, bolusInsulinName: p.bolusInsulinName,
                cgmModel: p.cgmModel, meterModel: p.meterModel, pumpModel: p.pumpModel,
                doctorName: p.doctorName, doctorPhone: p.doctorPhone,
                nextAppointment: p.nextAppointment)
        }
        backup.settings = Self.settingsSnapshot()
        return backup
    }

    /// Every preference the app stores, keyed exactly as `UserDefaults` holds it
    /// — the `pref.*` family from the shared App Group suite plus the two
    /// standard-defaults strays. The legacy background-photo blob is excluded on
    /// purpose: it can be megabytes and lives in its own file today.
    private static func settingsSnapshot() -> [String: JournalBackup.SettingValue] {
        var out: [String: JournalBackup.SettingValue] = [:]
        let group = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        for (key, value) in group.dictionaryRepresentation()
        where key.hasPrefix("pref.") && key != "pref.backgroundPhoto" {
            if let wrapped = JournalBackup.SettingValue(any: value) { out[key] = wrapped }
        }
        for key in standardDefaultsKeys {
            if let value = UserDefaults.standard.object(forKey: key),
               let wrapped = JournalBackup.SettingValue(any: value) {
                out[key] = wrapped
            }
        }
        return out
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
    /// journal never duplicates and never overwrites an edit. The same caution
    /// extends to the profile (filled only while still blank) and settings
    /// (written only for keys the user hasn't touched on this device).
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
        let favoriteIDs = existingIDs(FavoriteMeal.self, \.id)
        for r in backup.favorites where !favoriteIDs.contains(r.id) {
            let meal = FavoriteMeal(
                id: r.id, name: r.name, grams: r.grams,
                mealType: MealType(rawValue: r.mealTypeRaw) ?? .lunch,
                foodDescription: r.foodDescription)
            meal.usualMinutesFromMidnight = r.usualMinutesFromMidnight
            meal.timesUsed = r.timesUsed
            meal.lastUsedAt = r.lastUsedAt
            meal.createdAt = r.createdAt
            modelContext.insert(meal)
            inserted += 1
        }
        let labIDs = existingIDs(LabResult.self, \.id)
        for r in backup.labResults where !labIDs.contains(r.id) {
            modelContext.insert(LabResult(
                id: r.id, value: r.value, timestamp: r.timestamp, note: r.note))
            inserted += 1
        }
        let sensorIDs = existingIDs(SensorSession.self, \.id)
        for r in backup.sensorSessions where !sensorIDs.contains(r.id) {
            modelContext.insert(SensorSession(
                id: r.id, startDate: r.startDate,
                kind: SensorKind(rawValue: r.kindRaw) ?? .other,
                createdAt: r.createdAt))
            inserted += 1
        }
        if let record = backup.profile, restoreProfile(record) {
            inserted += 1
        }
        restoreSettings(backup.settings)

        try modelContext.save()
        return inserted
    }

    /// Applies the backed-up profile only where it cannot clobber anything: onto
    /// a store with no profile row, or onto the blank row first launch creates.
    /// A profile the user has already named stays exactly as it is.
    private func restoreProfile(_ record: JournalBackup.ProfileRecord) -> Bool {
        let existing = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
        if let existing, !existing.displayName.isEmpty { return false }
        guard !record.displayName.isEmpty || existing == nil else { return false }

        let target = existing ?? {
            let fresh = UserProfile(id: record.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.displayName = record.displayName
        target.avatarSymbol = record.avatarSymbol
        target.diabetesTypeRaw = record.diabetesTypeRaw
        target.therapyRaw = record.therapyRaw
        target.diagnosisYear = record.diagnosisYear
        target.careTeamNote = record.careTeamNote
        target.avatarColorHex = record.avatarColorHex
        target.avatarImageData = record.avatarImageData
        target.birthYear = record.birthYear
        target.weightKg = record.weightKg
        target.heightCm = record.heightCm
        target.basalInsulinName = record.basalInsulinName
        target.bolusInsulinName = record.bolusInsulinName
        target.cgmModel = record.cgmModel
        target.meterModel = record.meterModel
        target.pumpModel = record.pumpModel
        target.doctorName = record.doctorName
        target.doctorPhone = record.doctorPhone
        target.nextAppointment = record.nextAppointment
        target.updatedAt = Date()
        return true
    }

    /// Writes each backed-up setting only where this device has never stored a
    /// value for that key — a fresh install gets the whole configuration back,
    /// while every switch the user has touched here stays exactly as set.
    private func restoreSettings(_ settings: [String: JournalBackup.SettingValue]) {
        guard !settings.isEmpty else { return }
        let group = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        for (key, value) in settings {
            let target = key.hasPrefix("pref.") ? group : UserDefaults.standard
            if target.object(forKey: key) == nil {
                target.set(value.plistValue, forKey: key)
            }
        }
    }

    private func existingIDs<T: PersistentModel>(_ type: T.Type, _ keyPath: KeyPath<T, UUID>) -> Set<UUID> {
        let all = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        return Set(all.map { $0[keyPath: keyPath] })
    }
}
