import Foundation
import SwiftData
import Observation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

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
    let alerts: GlucoseAlertService

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
            NightscoutGlucoseSource(preferences: prefs),
            BluetoothGlucoseMeterSource(),
        ])
        self.registry = registry

        let audit = AuditService(context: context)
        self.audit = audit
        self.consent = ConsentStore(context: context, audit: audit)
        self.exporter = ExportService(audit: audit)
        self.notifications = NotificationScheduler()

        let alerts = GlucoseAlertService()
        self.alerts = alerts
        self.snapshots = SnapshotPublisher(context: context, preferences: prefs, registry: registry, alerts: alerts)
        self.sync = SyncCoordinator(context: context, registry: registry, audit: audit)
        self.entryStore = EntryStore(context: context, audit: audit, healthKit: healthKit,
                                     consent: consent, registry: registry)

        // Any write — a manual entry or a completed sync — republishes the
        // widget/watch snapshot and re-evaluates glucose alerts.
        let publisher = snapshots
        entryStore.onChange = { publisher.refresh() }
        sync.onChange = { publisher.refresh() }
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
        notifications.reschedule(from: preferences.reminders, glucoseSchedule: preferences.glucoseSchedule)
        scheduleBackgroundRefresh()
    }

    // MARK: Background refresh

    /// Identifier registered via the `.backgroundTask(.appRefresh(_:))` scene
    /// modifier and listed in `BGTaskSchedulerPermittedIdentifiers`.
    static let backgroundRefreshIdentifier = "com.prvital.refresh"

    /// Runs a full sync in the background, then queues the next refresh. Because
    /// sync republishes the snapshot, this also re-evaluates glucose alerts, so
    /// the app can notify the user while it isn't open.
    func performBackgroundRefresh() async {
        _ = await sync.syncAll()
        scheduleBackgroundRefresh()
    }

    /// Asks the system to run the app again in ~15 minutes (a request, not a
    /// guarantee — iOS decides the actual timing).
    func scheduleBackgroundRefresh() {
        #if canImport(BackgroundTasks) && os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
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
