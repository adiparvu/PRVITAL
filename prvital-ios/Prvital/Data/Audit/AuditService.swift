import Foundation
import SwiftData

/// Writes and reads the privacy audit trail.
///
/// Records the *fact* of a sensitive operation — source access, sync, export,
/// manual edit, permission change, conflict resolution, deletion — without
/// copying medical values into the log. A configurable retention window keeps
/// the trail from growing without bound.
@MainActor
final class AuditService {
    private let context: ModelContext
    /// Audit rows older than this are pruned on launch. Default 365 days.
    var retention: TimeInterval = 60 * 60 * 24 * 365

    init(context: ModelContext) { self.context = context }

    func log(
        _ action: AuditActionType,
        source: DataSource? = nil,
        userConfirmation: Bool = false,
        result: AuditResult = .success,
        detail: String? = nil
    ) {
        let record = PrivacyAuditRecord(
            actionType: action,
            dataSource: source,
            userConfirmation: userConfirmation,
            deviceIdentifier: DeviceIdentity.current,
            result: result,
            detail: detail
        )
        context.insert(record)
        try? context.save()
    }

    func recent(limit: Int = 200) -> [PrivacyAuditRecord] {
        var descriptor = FetchDescriptor<PrivacyAuditRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// High-churn row types (sync passes, conflict resolutions) age out much
    /// sooner than the year-long trail: they record routine plumbing, not user
    /// decisions, and at CGM cadence they dominate the table — an active user
    /// accrues ~300 sync rows a day, which within months makes every save and
    /// every audit-list fetch slower. 30 days keeps plenty for diagnostics.
    var routineRetention: TimeInterval = 60 * 60 * 24 * 30

    /// Removes rows older than the retention window — a long window for the
    /// user-action trail, a short one for routine plumbing rows.
    func pruneExpired(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        let routineCutoff = now.addingTimeInterval(-routineRetention)
        let syncRaw = AuditActionType.sync.rawValue
        let conflictRaw = AuditActionType.conflictResolution.rawValue
        let descriptor = FetchDescriptor<PrivacyAuditRecord>(
            predicate: #Predicate {
                $0.timestamp < cutoff
                    || ($0.timestamp < routineCutoff
                        && ($0.actionTypeRaw == syncRaw || $0.actionTypeRaw == conflictRaw))
            }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        stale.forEach(context.delete)
        try? context.save()
    }

    /// Runs `pruneExpired` at most once a day — cheap enough to call on every
    /// foreground activation without re-scanning the trail each time.
    func pruneIfDue(now: Date = Date()) {
        let key = "audit.lastPruneAt"
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: key)
        guard now.timeIntervalSince1970 - last > 24 * 60 * 60 else { return }
        defaults.set(now.timeIntervalSince1970, forKey: key)
        pruneExpired(now: now)
    }
}
