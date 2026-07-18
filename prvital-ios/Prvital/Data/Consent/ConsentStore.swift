import Foundation
import SwiftData
import Observation

/// The source of truth for per-scope consent.
///
/// Each `ConsentScope` is granted and revoked independently and every change is
/// mirrored into the audit trail, so the user is never asked to opt into
/// everything at once and can always see when a permission changed.
@MainActor
@Observable
final class ConsentStore {
    private let context: ModelContext
    private let audit: AuditService
    let policyVersion = "1.0.0"

    /// Current grant state per scope, kept in memory for instant UI reads.
    private(set) var grants: [ConsentScope: Bool] = [:]

    init(context: ModelContext, audit: AuditService) {
        self.context = context
        self.audit = audit
        reload()
    }

    func isGranted(_ scope: ConsentScope) -> Bool { grants[scope] ?? false }

    /// Records a consent decision and audits the change. This tracks the user's
    /// *intent*; the corresponding system authorization is requested separately.
    func setGranted(_ scope: ConsentScope, _ granted: Bool) {
        let record = record(for: scope) ?? {
            let new = ConsentRecord(scope: scope, granted: granted, policyVersion: policyVersion)
            context.insert(new)
            return new
        }()
        record.granted = granted
        record.updatedAt = Date()
        record.policyVersion = policyVersion
        try? context.save()
        grants[scope] = granted
        audit.log(.permissionChange, result: granted ? .granted : .revoked,
                  detail: "\(scope.title): \(granted ? "granted" : "revoked")")
    }

    /// True once the user has made a first pass through onboarding consent.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults(suiteName: AppSchema.appGroupIdentifier)?.bool(forKey: Self.onboardingKey) ?? false }
        set { UserDefaults(suiteName: AppSchema.appGroupIdentifier)?.set(newValue, forKey: Self.onboardingKey) }
    }
    private static let onboardingKey = "com.prvital.onboardingComplete"

    private func reload() {
        let records = (try? context.fetch(FetchDescriptor<ConsentRecord>())) ?? []
        var map: [ConsentScope: Bool] = [:]
        for record in records {
            if let scope = record.scope { map[scope] = record.granted }
        }
        grants = map
    }

    private func record(for scope: ConsentScope) -> ConsentRecord? {
        let raw = scope.rawValue
        let descriptor = FetchDescriptor<ConsentRecord>(
            predicate: #Predicate { $0.scopeRaw == raw }
        )
        return try? context.fetch(descriptor).first
    }
}
