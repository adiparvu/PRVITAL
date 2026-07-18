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

    /// Removes rows older than the retention window.
    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-retention)
        let descriptor = FetchDescriptor<PrivacyAuditRecord>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        stale.forEach(context.delete)
        try? context.save()
    }
}
