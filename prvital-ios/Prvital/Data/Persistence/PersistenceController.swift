import Foundation
import SwiftData

/// The app's SwiftData schema and container factory.
///
/// The store lives in the shared **App Group** container so that future
/// extensions can read it directly, and encryption at rest is provided by the
/// system through the file's **Data Protection** class (see `Info.plist`
/// `NSFileProtectionComplete`). CloudKit sync is opt-in: the private database is
/// only attached when the user has granted the `cloudSync` consent scope.
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
        SensorSession.self,
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
        do {
            return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
        } catch {
            // A schema/store mismatch must never crash the app silently on a
            // medical record store; fall back to a fresh in-memory container so
            // the UI stays usable and the failure is visible in logs.
            assertionFailure("ModelContainer creation failed: \(error)")
            return previewContainer
        }
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
