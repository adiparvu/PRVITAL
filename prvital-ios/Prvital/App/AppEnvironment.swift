import Foundation
import SwiftData
import Observation

/// The composition root. Owns the model container and wires every service and
/// store together, then is injected into the SwiftUI environment so features
/// depend on abstractions, never on construction.
@MainActor
@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let preferences: Preferences
    let healthKit: HealthKitService
    let registry: SourceRegistry
    let audit: AuditService
    let consent: ConsentStore
    let entryStore: EntryStore
    let sync: SyncCoordinator
    let snapshots: SnapshotPublisher
    let exporter: ExportService
    let notifications: NotificationScheduler

    init(modelContainer: ModelContainer, preferences: Preferences? = nil) {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext

        let prefs = preferences ?? Preferences()
        self.preferences = prefs

        let healthKit = HealthKitService()
        self.healthKit = healthKit

        let registry = SourceRegistry(sources: [
            ManualGlucoseSource(),
            HealthKitGlucoseSource(service: healthKit),
            DexcomGlucoseSource(),
            LibreGlucoseSource(),
        ])
        self.registry = registry

        let audit = AuditService(context: context)
        self.audit = audit
        self.consent = ConsentStore(context: context, audit: audit)
        self.exporter = ExportService(audit: audit)
        self.notifications = NotificationScheduler()

        self.snapshots = SnapshotPublisher(context: context, preferences: prefs, registry: registry)
        self.sync = SyncCoordinator(context: context, registry: registry, audit: audit)
        self.entryStore = EntryStore(context: context, audit: audit, healthKit: healthKit,
                                     consent: consent, registry: registry)

        // Any write republishes the widget/watch snapshot.
        let publisher = snapshots
        entryStore.onChange = { publisher.refresh() }
    }

    /// One-time launch work: prune the audit trail, seed demo data on a fresh
    /// install, wire the watch bridge, and publish the first snapshot.
    func bootstrap() {
        audit.pruneExpired()
        DemoData.seedIfEmpty(into: modelContainer.mainContext)

        // Log quick entries sent from the Apple Watch through the normal path.
        WatchSessionManager.shared.onQuickEntry = { [weak self] kind, amount in
            guard let self else { return }
            switch kind {
            case "insulin": self.entryStore.addInsulin(units: amount)
            case "carbs": self.entryStore.addCarbs(grams: amount)
            default: break
            }
        }
        WatchSessionManager.shared.activate()

        snapshots.refresh()
        notifications.reschedule(from: preferences.reminders)
    }

    // MARK: Factories

    static func live() -> AppEnvironment {
        AppEnvironment(modelContainer: PersistenceController.makeContainer())
    }

    /// In-memory environment seeded with demo data, for previews.
    static func preview() -> AppEnvironment {
        let container = PersistenceController.previewContainer
        let env = AppEnvironment(modelContainer: container)
        DemoData.seedIfEmpty(into: container.mainContext)
        env.snapshots.refresh()
        return env
    }
}
