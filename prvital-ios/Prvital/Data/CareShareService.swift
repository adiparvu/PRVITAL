import Foundation
import SwiftData

/// Assembles the shareable care summary from the store, profile and preferences.
/// The composing itself is pure (`CareSummaryComposer`); this just gathers the
/// inputs on the main actor.
@MainActor
final class CareShareService {
    private let context: ModelContext
    private let preferences: Preferences
    private let profileStore: ProfileStore
    private let audit: AuditService

    init(context: ModelContext, preferences: Preferences, profileStore: ProfileStore, audit: AuditService) {
        self.context = context
        self.preferences = preferences
        self.profileStore = profileStore
        self.audit = audit
    }

    /// Builds the care summary text for the last `days` days.
    func summaryText(days: Int = 14, now: Date = Date()) -> String {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= since }
        )
        let readings = (try? context.fetch(descriptor)) ?? []
        let stats = StatisticsEngine.glucose(readings, thresholds: preferences.thresholds)
        let profile = profileStore.current()
        let input = CareSummaryComposer.Input(
            name: profile.displayName,
            diabetesType: profile.diabetesType.displayName,
            therapy: profile.therapy.displayName,
            periodLabel: "Last \(days) days",
            unit: preferences.glucoseUnit,
            stats: stats,
            generatedAt: now
        )
        return CareSummaryComposer.text(input)
    }

    /// Records that a shareable summary of sensitive data was prepared, for the
    /// audit trail.
    func logPrepared() {
        audit.log(.export, userConfirmation: true, detail: "Care summary prepared for sharing")
    }
}
