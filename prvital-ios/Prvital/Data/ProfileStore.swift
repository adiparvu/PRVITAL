import Foundation
import SwiftData

/// Owns the single `UserProfile`, creating it on first use. There is exactly one
/// profile per store (this is a personal app, not a multi-tenant one); the
/// caregiver/partner story is handled by sharing (see the sharing feature), not
/// by multiple local profiles.
@MainActor
final class ProfileStore {
    private let context: ModelContext
    private let audit: AuditService

    /// Called after the profile is edited, so the app can react (e.g. refresh a
    /// header). Optional.
    var onChange: () -> Void = {}

    init(context: ModelContext, audit: AuditService) {
        self.context = context
        self.audit = audit
    }

    /// The current profile, fetched or created-and-inserted on first access.
    @discardableResult
    func current() -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Persists edits made to `profile` and stamps `updatedAt`.
    func save(_ profile: UserProfile) {
        profile.updatedAt = Date()
        try? context.save()
        audit.log(.manualEdit, userConfirmation: true, detail: "Profile updated")
        onChange()
    }
}
