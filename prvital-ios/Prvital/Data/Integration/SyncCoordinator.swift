import Foundation
import SwiftData

/// Orchestrates the full ingestion pipeline for external glucose sources:
///
///   integration (fetch) → normalization → dedup + storage
///     → conflict resolution → audit
///
/// It is the one place that ties the layers together, so a background task or a
/// pull-to-refresh both go through exactly the same, auditable path.
@MainActor
final class SyncCoordinator {
    private let context: ModelContext
    private let registry: SourceRegistry
    private let audit: AuditService

    /// How far back a first sync backfills when there is no prior data.
    var backfillWindow: TimeInterval = 60 * 60 * 24 * 3

    /// Guards against overlapping runs. With a foreground poller, a background
    /// refresh and HealthKit background-delivery observers all able to trigger a
    /// sync, two could otherwise interleave across an `await` and both insert the
    /// same not-yet-saved sample. `@MainActor` makes this flag check atomic.
    private var isSyncing = false

    /// Called after each sync finishes, so the app can republish the snapshot
    /// and re-evaluate alerts from any newly imported readings.
    var onChange: (() -> Void)?

    /// Imports the non-glucose journal (insulin, meals, activity) from Apple
    /// Health on the same pass. Injected by the composition root; nil in contexts
    /// (previews, tests) that don't wire HealthKit.
    var healthImporter: HealthDataImporter?

    init(context: ModelContext, registry: SourceRegistry, audit: AuditService) {
        self.context = context
        self.registry = registry
        self.audit = audit
    }

    struct SyncReport { var imported = 0; var conflicts = 0; var failures: [String] = [] }

    /// A full sync that backfills up to `backfillWindow`. Used by pull-to-refresh
    /// and background refresh.
    @discardableResult
    func syncAll() async -> SyncReport {
        await sync(since: Date().addingTimeInterval(-backfillWindow))
    }

    /// A light, frequent refresh that only pulls the recent window — used by the
    /// foreground live poller so it can update often without re-fetching days of
    /// data each time.
    @discardableResult
    func refreshLatest(window: TimeInterval = 30 * 60) async -> SyncReport {
        await sync(since: Date().addingTimeInterval(-max(window, 300)))
    }

    /// Pulls new samples from every connected source since `since` and integrates
    /// them.
    @discardableResult
    private func sync(since: Date) async -> SyncReport {
        // Skip if a sync is already running — the in-flight one covers this window.
        guard !isSyncing else { return SyncReport() }
        isSyncing = true
        defer { isSyncing = false }

        var report = SyncReport()

        for source in registry.connectedSources() {
            do {
                let samples = try await source.fetchSamples(since: since)
                let inserted = ingest(samples, from: source.source)
                report.imported += inserted
                audit.log(.sync, source: source.source, result: .success,
                          detail: "Imported \(inserted) reading(s)")
            } catch {
                // A source that simply isn't set up / needs re-linking (no valid
                // credentials, unavailable hardware) is an expected state, not a
                // refresh failure — don't surface it to the user or spam the audit
                // trail on every poll. Only genuine fetch errors (network, server)
                // are reported.
                if (error as? SourceError)?.isConfigurationState == true { continue }
                report.failures.append("\(source.displayName): \(error.localizedDescription)")
                audit.log(.sync, source: source.source, result: .failure,
                          detail: error.localizedDescription)
            }
        }

        // Fill in the rest of the journal — insulin, meals, activity — from Apple
        // Health on the same pass, so the timeline is complete, not just glucose.
        if let healthImporter {
            report.imported += await healthImporter.importRecords(since: since)
        }

        report.conflicts = resolveRecentConflicts(since: since)
        try? context.save()
        onChange?()
        return report
    }

    /// Inserts new (non-duplicate) samples for one source; returns the count.
    private func ingest(_ samples: [NormalizedGlucoseSample], from source: DataSource) -> Int {
        guard !samples.isEmpty else { return 0 }
        // Dedup within the incoming batch first — a source can report the same
        // instant twice in one payload (e.g. LibreLinkUp's current measurement plus
        // the newest graph point share one id), which would otherwise insert a
        // permanent phantom duplicate that DB-only dedup never catches.
        var seenInBatch = Set<String>()
        let unique = samples.filter { seenInBatch.insert($0.id).inserted }
        let incomingIDs = Set(unique.map(\.id))
        let existing = fetchExternalIDs(source: source, ids: incomingIDs)

        var inserted = 0
        for sample in unique where !existing.contains(sample.id) {
            context.insert(GlucoseNormalizer.reading(from: sample))
            inserted += 1
        }
        return inserted
    }

    /// Runs deterministic conflict resolution over the affected window and
    /// records a single audit row summarising the outcome.
    @discardableResult
    func resolveRecentConflicts(since: Date) -> Int {
        // Widen the window a few minutes so a conflict cluster straddling `since`
        // is re-resolved with all of its members — otherwise a previously
        // superseded reading looks like a singleton, gets reset to active, and the
        // instant is double-counted in averages/TIR.
        let windowedSince = since.addingTimeInterval(-300)
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= windowedSince },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let readings = try? context.fetch(descriptor), !readings.isEmpty else { return 0 }

        let resolver = ConflictResolver(sourcePriority: registry.sourcePriority)
        let summary = resolver.resolve(readings)
        if summary.groupCount > 0 {
            audit.log(.conflictResolution, result: .success,
                      detail: "Resolved \(summary.groupCount) conflict group(s), "
                            + "\(summary.conflictedReadingCount) reading(s)")
        }
        return summary.groupCount
    }

    private func fetchExternalIDs(source: DataSource, ids: Set<String>) -> Set<String> {
        let raw = source.rawValue
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { reading in
                reading.sourceRaw == raw && reading.externalID != nil
            }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.compactMap(\.externalID)).intersection(ids)
    }
}
