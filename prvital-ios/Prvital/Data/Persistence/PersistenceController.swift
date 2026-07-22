import Foundation
import SwiftData

/// The app's SwiftData schema and container factory.
///
/// The store lives in the shared **App Group** container so that future
/// extensions can read it directly, and encryption at rest is provided by the
/// system through the file's **Data Protection** class
/// (`NSFileProtectionCompleteUntilFirstUserAuthentication` — encrypted at rest,
/// but readable after the first unlock following a reboot so a background launch
/// can still open it). CloudKit sync is opt-in: the private database is only
/// attached when the user has granted the `cloudSync` consent scope.
enum AppSchema {
    static let appGroupIdentifier = "group.com.prvital"
    static let cloudKitContainerIdentifier = "iCloud.com.prvital"

    static let models: [any PersistentModel.Type] = [
        GlucoseReading.self,
        InsulinDose.self,
        CarbEntry.self,
        ActivityEntry.self,
        ObservationEntry.self,
        FoodItem.self,
        FavoriteMeal.self,
        SensorSession.self,
        MedicationDose.self,
        LabResult.self,
        KetoneReading.self,
        UserProfile.self,
        PrivacyAuditRecord.self,
        ConsentRecord.self,
    ]

    static var schema: Schema { Schema(models) }
}

@MainActor
enum PersistenceController {

    /// The production container. Local-only by default; pass `cloudSync: true`
    /// once the user has consented to iCloud sync.
    static func makeContainer(cloudSync: Bool = false) -> ModelContainer {
        let configuration = makeConfiguration(cloudSync: cloudSync)
        // Installs created before the protection-class change wrote the store
        // with NSFileProtectionComplete, and that attribute is sticky on the file
        // even after the entitlement default changes. Relax it so the store can
        // be opened by a background launch after the first unlock — otherwise the
        // container fails to open and the app comes up empty ("data gone after
        // reboot"). Best-effort: if the device is still locked this throws and we
        // simply proceed (the entitlement default covers freshly-created files).
        relaxFileProtection(for: configuration)
        relaxAppGroupPreferences()
        do {
            return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
        } catch {
            // Retry once: a transient failure (e.g. the store was momentarily
            // unavailable) must not drop the user into an empty store.
            if let retry = try? ModelContainer(for: AppSchema.schema, configurations: [configuration]) {
                return retry
            }
            // Last resort only: a fresh in-memory container keeps the UI usable
            // WITHOUT touching or overwriting the on-disk store, so the real data
            // is never destroyed and returns on the next successful launch.
            assertionFailure("ModelContainer creation failed: \(error)")
            return previewContainer
        }
    }

    /// Downgrades the store (and its `-wal` / `-shm` sidecars) from
    /// `NSFileProtectionComplete` to `…CompleteUntilFirstUserAuthentication`, so
    /// it stays readable while the app runs in the background after the first
    /// post-reboot unlock. No-op for files that don't exist yet or can't be
    /// reached (device still locked).
    private static func relaxFileProtection(for configuration: ModelConfiguration) {
        let storePath = configuration.url.path
        let fileManager = FileManager.default
        for path in [storePath, storePath + "-wal", storePath + "-shm"]
        where fileManager.fileExists(atPath: path) {
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: path)
        }
    }

    /// The widgets read their glucose snapshot from the App Group `UserDefaults`,
    /// whose backing plist inherited the same sticky `NSFileProtectionComplete`
    /// on upgrading installs — making it unreadable while the device is locked,
    /// which is exactly when Lock Screen / background widgets refresh. Relax it to
    /// match, so the snapshot stays readable and the widgets don't show "No data".
    private static func relaxAppGroupPreferences() {
        let fileManager = FileManager.default
        guard let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: AppSchema.appGroupIdentifier) else { return }
        let plist = container
            .appending(path: "Library/Preferences/\(AppSchema.appGroupIdentifier).plist")
        guard fileManager.fileExists(atPath: plist.path) else { return }
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: plist.path)
    }

    private static func makeConfiguration(cloudSync: Bool) -> ModelConfiguration {
        let cloudKit: ModelConfiguration.CloudKitDatabase = cloudSync
            ? .private(AppSchema.cloudKitContainerIdentifier)
            : .none

        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppSchema.appGroupIdentifier)?
            .appending(path: "Prvital.store") {
            return ModelConfiguration(schema: AppSchema.schema, url: url, cloudKitDatabase: cloudKit)
        }
        // No App Group entitlement (e.g. unit tests): use the default location.
        return ModelConfiguration(schema: AppSchema.schema, cloudKitDatabase: cloudKit)
    }

    /// In-memory container for SwiftUI previews and tests.
    static let previewContainer: ModelContainer = {
        let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: AppSchema.schema, configurations: [configuration])
    }()
}
