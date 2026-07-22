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
    let profile: ProfileStore
    let careShare: CareShareService
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
        self.profile = ProfileStore(context: context, audit: audit)
        self.careShare = CareShareService(context: context, preferences: prefs,
                                          profileStore: self.profile, audit: audit)

        // Any write — a manual entry or a completed sync — republishes the
        // widget/watch snapshot, re-evaluates glucose alerts, and refreshes the
        // data-driven contextual reminders.
        let publisher = snapshots
        entryStore.onChange = { [weak self] in
            publisher.refresh()
            self?.rescheduleContextualReminders()
        }
        sync.onChange = { [weak self] in
            publisher.refresh()
            self?.rescheduleContextualReminders()
        }

        // Every sync also pulls insulin, meals and activity from Apple Health so
        // the journal is the full picture, not only the glucose curve.
        sync.healthImporter = HealthDataImporter(context: context, healthKit: healthKit, consent: consent)

        // And, when the user opts in, mirrors their own manual entries up to
        // their Nightscout site after each successful sync pass.
        sync.nightscoutUploader = NightscoutUploader(preferences: prefs, audit: audit)
    }

    /// One-time launch work: prune the audit trail, clean up any sample data an
    /// earlier build seeded, wire the watch bridge, and publish the first
    /// snapshot. The live app never seeds demo data — it shows only the user's
    /// own readings and entries.
    func bootstrap() {
        audit.pruneExpired()
        DemoData.removeSeededDataOnce(from: modelContainer.mainContext)

        // Log quick entries sent from the Apple Watch through the normal path.
        WatchSessionManager.shared.onQuickEntry = { [weak self] kind, amount in
            guard let self else { return }
            switch kind {
            case "insulin": self.entryStore.addInsulin(units: amount)
            case "carbs": self.entryStore.addCarbs(grams: amount)
            case "glucose": self.entryStore.addGlucose(mgdL: amount)
            default: break
            }
        }
        WatchSessionManager.shared.activate()

        _ = profile.current()   // create the single profile on first launch
        snapshots.refresh()
        // Repopulate the widgets from the (now file-backed) snapshot immediately on
        // launch — upgrading installs move from the unreadable UserDefaults plist to
        // the App Group file, and this makes that switch visible without waiting on
        // the reload budget.
        snapshots.reloadWidgets()
        notifications.reschedule(from: preferences.reminders, glucoseSchedule: preferences.glucoseSchedule,
                                 medicationPlan: preferences.medicationPlan)
        rescheduleContextualReminders()
        WeeklyDigestScheduler().update(enabled: preferences.weeklyDigestEnabled)
        scheduleBackgroundRefresh()
        startHealthKitBackgroundDelivery()
    }

    /// Wires Apple Health background delivery: while the user has granted the
    /// HealthKit scope, new Health data (a fresh CGM reading, a logged meal, a
    /// finished workout) wakes the app in the background to sync and republish the
    /// snapshot — so the journal, widgets and Live Activity update even when the
    /// app isn't open. The `BGAppRefreshTask` above stays as a periodic fallback.
    private func startHealthKitBackgroundDelivery() {
        guard consent.isGranted(.healthKit) else { return }
        BackgroundSyncBridge.environment = self
        let hk = healthKit
        Task { await hk.enableBackgroundDelivery() }
        hk.startObserving {
            // Fires on an arbitrary queue; hop to the main actor via the bridge,
            // which avoids capturing this non-Sendable environment in the closure.
            Task { @MainActor in await BackgroundSyncBridge.handleExternalDataChange() }
        }
    }

    /// A light, recent-window sync triggered by a HealthKit background-delivery
    /// wake. Republishes the snapshot (updating widgets + Live Activity) and
    /// re-evaluates alerts, without rescheduling the BG app-refresh task.
    func handleHealthKitBackgroundDelivery() async {
        _ = await sync.refreshLatest(window: 3 * 60 * 60)
    }

    // MARK: Contextual reminders

    /// Rebuilds the data-driven contextual reminders from the most recent reading,
    /// meal and dose, then hands them to the scheduler (which cancels the previous
    /// batch by identifier). Cheap — three `fetchLimit == 1` queries — so it's fine
    /// to run on every data change.
    ///
    /// The feature stays opt-in without a new preference by reusing the user's
    /// existing reminder switches: the reading-gap nudge follows the glucose-check
    /// reminder opt-in, and the meal-driven nudges follow the meal reminder opt-in.
    /// Both default off, so nothing fires unprompted.
    func rescheduleContextualReminders(now: Date = Date()) {
        let context = modelContainer.mainContext
        let meal = Self.latestMeal(in: context)
        let input = ContextualReminderInput(
            lastReadingAt: Self.latestActiveReadingTimestamp(in: context),
            lastMealAt: meal?.timestamp,
            lastMealCarbs: meal?.grams,
            lastInsulinAt: Self.latestInsulinTimestamp(in: context)
        )
        // Sick-day mode tightens the reading-gap cadence (2h instead of 4h) while
        // it's on — but only for the already-opt-in glucose-check reminder, so it
        // never introduces a notification the user didn't ask for.
        let settings = ContextualReminderSettings(
            readingGapEnabled: preferences.reminders.glucoseCheckEnabled,
            mealContextEnabled: preferences.reminders.mealsEnabled,
            readingGapHours: preferences.sickDayEnabled ? 2 : 4
        )
        let due = ContextualReminderEvaluator.evaluate(input: input, settings: settings, now: now)
        notifications.rescheduleContextual(due)
    }

    private static func latestActiveReadingTimestamp(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp
    }

    private static func latestMeal(in context: ModelContext) -> CarbEntry? {
        var descriptor = FetchDescriptor<CarbEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func latestInsulinTimestamp(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<InsulinDose>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp
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

/// A tiny main-actor hand-off between HealthKit's background-delivery observer
/// and the current `AppEnvironment`.
///
/// The observer handler fires on an arbitrary queue with a `@Sendable` callback,
/// so it can't capture the non-Sendable `@MainActor AppEnvironment` directly.
/// Instead it references this type (a value-free enum), hops to the main actor,
/// and reads the weakly-held current environment there.
@MainActor
enum BackgroundSyncBridge {
    weak static var environment: AppEnvironment?

    static func handleExternalDataChange() async {
        await environment?.handleHealthKitBackgroundDelivery()
    }
}
