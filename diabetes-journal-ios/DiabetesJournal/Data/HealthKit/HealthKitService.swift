import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Wraps HealthKit read/write for glucose, insulin, carbohydrates and workouts.
///
/// Reads pull samples already in Apple Health (including those written by other
/// CGM apps); writes mirror the user's manual entries back so the rest of the
/// Health ecosystem sees them. All access is gated by the `healthKit` consent
/// scope and the system authorization sheet.
///
/// `@unchecked Sendable`: its only stored state is an `HKHealthStore`, which
/// Apple documents as thread-safe, so instances can be used from a detached
/// write task. Write methods take Sendable primitives (never `@Model` objects)
/// so nothing non-Sendable crosses an isolation boundary.
final class HealthKitService: @unchecked Sendable {
    #if canImport(HealthKit)
    private let store = HKHealthStore()

    private let glucoseUnit = HKUnit(from: "mg/dL")

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var glucoseType: HKQuantityType { HKQuantityType(.bloodGlucose) }
    private var insulinType: HKQuantityType { HKQuantityType(.insulinDelivery) }
    private var carbType: HKQuantityType { HKQuantityType(.dietaryCarbohydrates) }

    private var shareTypes: Set<HKSampleType> {
        [glucoseType, insulinType, carbType, HKObjectType.workoutType()]
    }
    private var readTypes: Set<HKObjectType> {
        [glucoseType, insulinType, carbType, HKObjectType.workoutType()]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw SourceError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    var glucoseAuthorization: HKAuthorizationStatus {
        isAvailable ? store.authorizationStatus(for: glucoseType) : .notDetermined
    }

    // MARK: Reads

    func fetchGlucoseSamples(since date: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [NormalizedGlucoseSample] {
        let samples = try await quantitySamples(of: glucoseType, since: date, limit: limit)
        return samples.map { sample in
            NormalizedGlucoseSample(
                id: sample.uuid.uuidString,
                valueMgdL: sample.quantity.doubleValue(for: glucoseUnit),
                timestamp: sample.startDate,
                source: .appleHealth,
                measurementType: .cgm,
                sensorTimestamp: sample.startDate,
                confidence: nil,
                deviceID: sample.sourceRevision.source.name
            )
        }
    }

    func fetchLatestGlucose() async throws -> NormalizedGlucoseSample? {
        try await fetchGlucoseSamples(since: .distantPast, limit: 1).first
    }

    private func quantitySamples(of type: HKQuantityType, since date: Date, limit: Int) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: SourceError.underlying(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: Write-back

    // Write methods take Sendable primitives so callers never pass a
    // non-Sendable `@Model` object across the isolation boundary into the task.

    func saveGlucose(mgdL: Double, at date: Date) async throws {
        let quantity = HKQuantity(unit: glucoseUnit, doubleValue: mgdL)
        let sample = HKQuantitySample(type: glucoseType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    func saveInsulin(units: Double, isBasal: Bool, at date: Date) async throws {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        let reason: HKInsulinDeliveryReason = isBasal ? .basal : .bolus
        let metadata: [String: Any] = [HKMetadataKeyInsulinDeliveryReason: reason.rawValue]
        let sample = HKQuantitySample(type: insulinType, quantity: quantity, start: date, end: date, metadata: metadata)
        try await store.save(sample)
    }

    func saveCarbs(grams: Double, at date: Date) async throws {
        let quantity = HKQuantity(unit: .gram(), doubleValue: grams)
        let sample = HKQuantitySample(type: carbType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }
    #else
    // Non-Apple platforms (Linux CI for the shared package): HealthKit is absent.
    var isAvailable: Bool { false }
    func requestAuthorization() async throws { throw SourceError.unavailable }
    func fetchGlucoseSamples(since date: Date, limit: Int = 0) async throws -> [NormalizedGlucoseSample] { [] }
    func fetchLatestGlucose() async throws -> NormalizedGlucoseSample? { nil }
    func saveGlucose(mgdL: Double, at date: Date) async throws {}
    func saveInsulin(units: Double, isBasal: Bool, at date: Date) async throws {}
    func saveCarbs(grams: Double, at date: Date) async throws {}
    #endif
}
