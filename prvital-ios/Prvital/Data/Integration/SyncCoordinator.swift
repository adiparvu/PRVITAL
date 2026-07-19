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

    /// Called after each sync finishes, so the app can republish the snapshot
    /// and re-evaluate alerts from any newly imported readings.
    var onChange: (() -> Void)?

    init(context: ModelContext, registry: SourceRegistry, audit: AuditService) {
        self.context = context
        self.registry = registry
        self.audit = audit
    }

    struct SyncReport { var imported = 0; var conflicts = 0; var failures: [String] = [] }

    /// Pulls new samples from every connected source and integrates them.
    @discardableResult
    func syncAll() async -> SyncReport {
        var report = SyncReport()
        let since = Date().addingTimeInterval(-backfillWindow)

        for source in registry.connectedSources() {
            do {
                let samples = try await source.fetchSamples(since: since)
                let inserted = ingest(samples, from: source.source)
                report.imported += inserted
                audit.log(.sync, source: source.source, result: .success,
                          detail: "Imported \(inserted) reading(s)")
            } catch {
                report.failures.append("\(source.displayName): \(error.localizedDescription)")
                audit.log(.sync, source: source.source, result: .failure,
                          detail: error.localizedDescription)
            }
        }

        report.conflicts = resolveRecentConflicts(since: since)
        try? context.save()
        onChange?()
        return report
    }

    /// Inserts new (non-duplicate) samples for one source; returns the count.
    private func ingest(_ samples: [NormalizedGlucoseSample], from source: DataSource) -> Int {
        guard !samples.isEmpty else { return 0 }
        let incomingIDs = Set(samples.map(\.id))
        let existing = fetchExternalIDs(source: source, ids: incomingIDs)

        var inserted = 0
        for sample in samples where !existing.contains(sample.id) {
            context.insert(GlucoseNormalizer.reading(from: sample))
            inserted += 1
        }
        return inserted
    }

    /// Runs deterministic conflict resolution over the affected window and
    /// records a single audit row summarising the outcome.
    @discardableResult
    func resolveRecentConflicts(since: Date) -> Int {
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= since },
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
