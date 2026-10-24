import XCTest
import SwiftData
@testable import Prvital

/// The backup promise, tested against real stores rather than just its file
/// format: everything comes back, nothing is duplicated, and nothing that is
/// already on the device is ever overwritten.
@MainActor
final class JournalBackupRestoreTests: XCTestCase {

    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
    }

    /// One record of every family the backup carries, plus a named profile.
    private func seed(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(GlucoseReading(valueMgdL: 111, timestamp: t, source: .manual, measurementType: .manual))
        context.insert(InsulinDose(units: 4, timestamp: t, insulinType: .rapidActing))
        context.insert(CarbEntry(grams: 45, timestamp: t, mealType: .lunch, foodDescription: "Pasta", note: nil))
        context.insert(ActivityEntry(activityType: .walking, startTimestamp: t, durationSeconds: 1800,
                                     intensity: .moderate, caloriesBurned: 120, distanceMeters: 2000, note: nil))
        context.insert(ObservationEntry(tags: [], text: "Felt tired", timestamp: t))
        context.insert(MedicationDose(id: UUID(), name: "Metformin", kind: .other, amount: 500,
                                      unitText: "mg", timestamp: t, note: nil))
        context.insert(KetoneReading(id: UUID(), value: 0.6, sample: .blood, timestamp: t, note: nil))
        context.insert(FavoriteMeal(id: UUID(), name: "Usual breakfast", grams: 45, mealType: .lunch, foodDescription: nil))
        context.insert(LabResult(id: UUID(), value: 6.8, timestamp: t, note: "clinic"))
        context.insert(SensorSession(id: UUID(), startDate: t, kind: .dexcomG7, createdAt: t))
        context.insert(UserProfile(displayName: "Ada", diabetesType: .type1, therapy: .mdi))
        try context.save()
    }

    private func count<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) -> Int {
        (try? ModelContext(container).fetchCount(FetchDescriptor<T>())) ?? -1
    }

    private func writeBackup(of container: ModelContainer) async throws -> URL {
        let url = try await JournalBackupStore(modelContainer: container).writeBackupFile()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: Everything comes back

    func testRestoreIntoAnEmptyStoreBringsBackEveryFamily() async throws {
        let source = try makeContainer()
        try seed(source)
        let url = try await writeBackup(of: source)

        let target = try makeContainer()
        let inserted = try await JournalBackupStore(modelContainer: target).restore(from: url)
        XCTAssertEqual(inserted, 11, "ten record families plus the profile")

        XCTAssertEqual(count(GlucoseReading.self, in: target), 1)
        XCTAssertEqual(count(InsulinDose.self, in: target), 1)
        XCTAssertEqual(count(CarbEntry.self, in: target), 1)
        XCTAssertEqual(count(ActivityEntry.self, in: target), 1)
        XCTAssertEqual(count(ObservationEntry.self, in: target), 1)
        XCTAssertEqual(count(MedicationDose.self, in: target), 1)
        XCTAssertEqual(count(KetoneReading.self, in: target), 1)
        XCTAssertEqual(count(FavoriteMeal.self, in: target), 1)
        XCTAssertEqual(count(LabResult.self, in: target), 1)
        XCTAssertEqual(count(SensorSession.self, in: target), 1)
        XCTAssertEqual(count(UserProfile.self, in: target), 1)

        // The values, not just the rows.
        let context = ModelContext(target)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GlucoseReading>()).first?.valueMgdL, 111)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InsulinDose>()).first?.units, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CarbEntry>()).first?.foodDescription, "Pasta")
        XCTAssertEqual(try context.fetch(FetchDescriptor<LabResult>()).first?.value, 6.8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FavoriteMeal>()).first?.name, "Usual breakfast")
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Ada")

        // Same records, not look-alikes: the ids survive the trip.
        let sourceID = try ModelContext(source).fetch(FetchDescriptor<InsulinDose>()).first?.id
        XCTAssertNotNil(sourceID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InsulinDose>()).first?.id, sourceID)
    }

    func testRestoringTheSameBackupAgainAddsNothing() async throws {
        let source = try makeContainer()
        try seed(source)
        let url = try await writeBackup(of: source)

        let target = try makeContainer()
        let store = JournalBackupStore(modelContainer: target)
        _ = try await store.restore(from: url)
        let again = try await store.restore(from: url)

        XCTAssertEqual(again, 0)
        XCTAssertEqual(count(GlucoseReading.self, in: target), 1)
        XCTAssertEqual(count(InsulinDose.self, in: target), 1)
        XCTAssertEqual(count(UserProfile.self, in: target), 1)
    }

    // MARK: Nothing is overwritten

    func testRestoreNeverOverwritesWhatIsAlreadyOnTheDevice() async throws {
        let source = try makeContainer()
        try seed(source)
        let sharedID = try XCTUnwrap(ModelContext(source).fetch(FetchDescriptor<GlucoseReading>()).first?.id)
        let url = try await writeBackup(of: source)

        // This device already holds that reading — edited since — and has its own profile.
        let target = try makeContainer()
        let existing = ModelContext(target)
        existing.insert(GlucoseReading(id: sharedID, valueMgdL: 200, timestamp: t, source: .manual, measurementType: .manual))
        existing.insert(UserProfile(displayName: "Grace", diabetesType: .type1, therapy: .mdi))
        try existing.save()

        let inserted = try await JournalBackupStore(modelContainer: target).restore(from: url)
        XCTAssertEqual(inserted, 9, "the reading and the profile were already there; the other nine records were not")

        let context = ModelContext(target)
        let readings = try context.fetch(FetchDescriptor<GlucoseReading>())
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.valueMgdL, 200, "the device's own edit wins")
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.displayName, "Grace", "a profile the person already named is left alone")
    }

    func testABlankFirstLaunchProfileIsFilledNotDuplicated() async throws {
        let source = try makeContainer()
        try seed(source)
        let url = try await writeBackup(of: source)

        // A fresh install creates an empty profile on first launch.
        let target = try makeContainer()
        let fresh = ModelContext(target)
        fresh.insert(UserProfile())
        try fresh.save()

        _ = try await JournalBackupStore(modelContainer: target).restore(from: url)
        let profiles = try ModelContext(target).fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.displayName, "Ada")
    }

    // MARK: Older files

    func testAVersionOneFileStillRestores() async throws {
        let v1 = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z",
         "glucose":[{"id":"22222222-2222-2222-2222-222222222222",
                     "timestamp":"2026-01-01T08:00:00Z","valueMgdL":112,
                     "sourceRaw":"manual","measurementTypeRaw":"manual","isActive":true}],
         "insulin":[],"carbs":[],"activity":[],"observations":[],"medications":[],"ketones":[]}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString).json")
        try Data(v1.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let target = try makeContainer()
        let inserted = try await JournalBackupStore(modelContainer: target).restore(from: url)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(count(GlucoseReading.self, in: target), 1)
        XCTAssertEqual(count(UserProfile.self, in: target), 0, "a v1 file has no profile to invent")
    }

    // MARK: Settings

    func testSettingsAreFilledOnlyWhereTheDeviceHasNone() async throws {
        // Real shared defaults, unique probe keys, always cleaned up.
        let group = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        let lost = "pref.test.backupProbeLost"
        let changed = "pref.test.backupProbeChanged"
        addTeardownBlock {
            let defaults = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
            defaults.removeObject(forKey: "pref.test.backupProbeLost")
            defaults.removeObject(forKey: "pref.test.backupProbeChanged")
        }
        group.set(7, forKey: lost)
        group.set("original", forKey: changed)

        let url = try await writeBackup(of: try makeContainer())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(JournalBackup.self, from: Data(contentsOf: url))
        XCTAssertEqual(backup.settings[lost], .int(7))
        XCTAssertEqual(backup.settings[changed], .string("original"))

        // A new device: one setting never existed, the other was changed since.
        group.removeObject(forKey: lost)
        group.set("changed on this device", forKey: changed)

        _ = try await JournalBackupStore(modelContainer: try makeContainer()).restore(from: url)
        XCTAssertEqual(group.integer(forKey: lost), 7, "a setting this device never had comes back")
        XCTAssertEqual(group.string(forKey: changed), "changed on this device", "a setting already chosen here is kept")
    }
}
