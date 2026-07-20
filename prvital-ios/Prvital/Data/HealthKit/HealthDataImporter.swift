import Foundation
import SwiftData

/// Imports the non-glucose parts of the journal — insulin, meals (carbs) and
/// activity — from Apple Health, so the timeline is complete and not just the
/// CGM curve. Glucose keeps flowing through `SyncCoordinator`/`HealthKitGlucoseSource`;
/// this fills in everything else the user (or another app, or a pump) logged.
///
/// Records are deduped by the Apple Health sample UUID (stored in `externalID`)
/// and tagged `source = .appleHealth`. The importer only **inserts** — it never
/// saves the context or fires change callbacks; `SyncCoordinator` owns the single
/// save + snapshot refresh so one sync produces one widget/Live Activity update.
@MainActor
final class HealthDataImporter {
    private let context: ModelContext
    private let healthKit: HealthKitService
    private let consent: ConsentStore

    init(context: ModelContext, healthKit: HealthKitService, consent: ConsentStore) {
        self.context = context
        self.healthKit = healthKit
        self.consent = consent
    }

    /// Pulls insulin, carbs and workouts since `since` and inserts the new ones.
    /// Returns how many records were inserted. A no-op unless the user granted the
    /// HealthKit scope and Health data is available.
    @discardableResult
    func importRecords(since: Date) async -> Int {
        guard consent.isGranted(.healthKit), healthKit.isAvailable else { return 0 }

        var inserted = 0
        if let insulin = try? await healthKit.fetchInsulinSamples(since: since) {
            inserted += insertInsulin(insulin)
        }
        if let carbs = try? await healthKit.fetchCarbSamples(since: since) {
            inserted += insertCarbs(carbs)
        }
        if let workouts = try? await healthKit.fetchWorkoutSamples(since: since) {
            inserted += insertWorkouts(workouts)
        }
        return inserted
    }

    // MARK: Inserts (deduped by Apple Health UUID)

    private func insertInsulin(_ samples: [HealthInsulinSample]) -> Int {
        guard !samples.isEmpty else { return 0 }
        let known = existingInsulinIDs(Set(samples.map(\.id)))
        var count = 0
        for sample in samples where !known.contains(sample.id) {
            let dose = InsulinDose(
                units: sample.units,
                timestamp: sample.timestamp,
                insulinType: sample.isBasal ? .longActing : .rapidActing,
                deliveryMethod: .pen,
                doseContext: sample.isBasal ? .basal : .mealBolus,
                source: .appleHealth
            )
            dose.externalID = sample.id
            dose.deviceID = sample.deviceName
            context.insert(dose)
            count += 1
        }
        return count
    }

    private func insertCarbs(_ samples: [HealthCarbSample]) -> Int {
        guard !samples.isEmpty else { return 0 }
        let known = existingCarbIDs(Set(samples.map(\.id)))
        var count = 0
        for sample in samples where !known.contains(sample.id) {
            let entry = CarbEntry(
                grams: sample.grams,
                timestamp: sample.timestamp,
                mealType: MealTimeClassifier.mealType(for: sample.timestamp),
                source: .appleHealth
            )
            entry.externalID = sample.id
            entry.deviceID = sample.deviceName
            context.insert(entry)
            count += 1
        }
        return count
    }

    private func insertWorkouts(_ samples: [HealthWorkoutSample]) -> Int {
        guard !samples.isEmpty else { return 0 }
        let known = existingActivityIDs(Set(samples.map(\.id)))
        var count = 0
        for sample in samples where !known.contains(sample.id) {
            let entry = ActivityEntry(
                activityType: sample.activity,
                startTimestamp: sample.startDate,
                durationSeconds: sample.durationSeconds,
                source: .appleHealth
            )
            entry.externalID = sample.id
            entry.deviceID = sample.deviceName
            context.insert(entry)
            count += 1
        }
        return count
    }

    // MARK: Existing-ID lookups

    private func existingInsulinIDs(_ ids: Set<String>) -> Set<String> {
        let raw = DataSource.appleHealth.rawValue
        let descriptor = FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.sourceRaw == raw && $0.externalID != nil }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.compactMap(\.externalID)).intersection(ids)
    }

    private func existingCarbIDs(_ ids: Set<String>) -> Set<String> {
        let raw = DataSource.appleHealth.rawValue
        let descriptor = FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.sourceRaw == raw && $0.externalID != nil }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.compactMap(\.externalID)).intersection(ids)
    }

    private func existingActivityIDs(_ ids: Set<String>) -> Set<String> {
        let raw = DataSource.appleHealth.rawValue
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.sourceRaw == raw && $0.externalID != nil }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.compactMap(\.externalID)).intersection(ids)
    }
}
