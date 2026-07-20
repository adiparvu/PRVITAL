import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// A Sendable projection of an Apple Health insulin-delivery sample, so the value
/// crosses from the nonisolated HealthKit query into the `@MainActor` importer
/// without carrying any HealthKit type.
struct HealthInsulinSample: Sendable {
    let id: String
    let units: Double
    let isBasal: Bool
    let timestamp: Date
    let deviceName: String?
}

/// A Sendable projection of an Apple Health dietary-carbohydrates sample.
struct HealthCarbSample: Sendable {
    let id: String
    let grams: Double
    let timestamp: Date
    let deviceName: String?
}

/// A Sendable projection of an Apple Health workout, mapped to our `ActivityType`.
struct HealthWorkoutSample: Sendable {
    let id: String
    let activity: ActivityType
    let startDate: Date
    let durationSeconds: Int
    let deviceName: String?
}

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
        return samples.compactMap { sample in
            // Skip readings we mirrored to Apple Health ourselves — otherwise a
            // manual glucose entry round-trips back in as a duplicate .appleHealth
            // reading (and, since .appleHealth outranks .manual, its provenance
            // would silently flip from Manual to Apple Health).
            guard !isOwnSample(sample) else { return nil }
            return NormalizedGlucoseSample(
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

    // MARK: Reads — insulin, carbs, workouts (for the full journal timeline)

    /// The app's own bundle id, so imports can skip the samples we mirrored to
    /// Apple Health ourselves — otherwise a manual entry would round-trip back in
    /// as a duplicate `.appleHealth` record.
    private var ownBundleIdentifier: String? { Bundle.main.bundleIdentifier }

    private func isOwnSample(_ sample: HKSample) -> Bool {
        guard let own = ownBundleIdentifier else { return false }
        return sample.sourceRevision.source.bundleIdentifier == own
    }

    func fetchInsulinSamples(since date: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [HealthInsulinSample] {
        let samples = try await quantitySamples(of: insulinType, since: date, limit: limit)
        return samples.compactMap { sample in
            guard !isOwnSample(sample) else { return nil }
            let reasonRaw = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int
            let isBasal = reasonRaw == HKInsulinDeliveryReason.basal.rawValue
            return HealthInsulinSample(
                id: sample.uuid.uuidString,
                units: sample.quantity.doubleValue(for: .internationalUnit()),
                isBasal: isBasal,
                timestamp: sample.startDate,
                deviceName: sample.sourceRevision.source.name
            )
        }
    }

    func fetchCarbSamples(since date: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [HealthCarbSample] {
        let samples = try await quantitySamples(of: carbType, since: date, limit: limit)
        return samples.compactMap { sample in
            guard !isOwnSample(sample) else { return nil }
            return HealthCarbSample(
                id: sample.uuid.uuidString,
                grams: sample.quantity.doubleValue(for: .gram()),
                timestamp: sample.startDate,
                deviceName: sample.sourceRevision.source.name
            )
        }
    }

    func fetchWorkoutSamples(since date: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [HealthWorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: SourceError.underlying(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
        return workouts.compactMap { workout in
            guard !isOwnSample(workout) else { return nil }
            return HealthWorkoutSample(
                id: workout.uuid.uuidString,
                activity: Self.activityType(for: workout.workoutActivityType),
                startDate: workout.startDate,
                durationSeconds: Int(workout.duration),
                deviceName: workout.sourceRevision.source.name
            )
        }
    }

    /// Maps HealthKit's rich workout taxonomy onto our small `ActivityType` set;
    /// anything not explicitly matched is recorded as a generic gym session.
    private static func activityType(for hk: HKWorkoutActivityType) -> ActivityType {
        switch hk {
        case .walking, .hiking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .swimming: return .swimming
        default: return .gym
        }
    }

    // MARK: Background delivery

    /// Live observer queries, kept alive for the app's lifetime. Registered once
    /// from the main actor at launch.
    private var observerQueries: [HKObserverQuery] = []

    /// Asks Apple Health to wake the app when new glucose/insulin/carb/workout data
    /// arrives, so the journal, widgets and Live Activity stay current even when
    /// the app is only in the background. A no-op if the capability is unavailable.
    func enableBackgroundDelivery() async {
        for type in [glucoseType, insulinType, carbType] {
            try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
        try? await store.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .hourly)
    }

    /// Registers observer queries whose handler calls `onChange` whenever Health
    /// data of interest changes. `onChange` is `@Sendable` and must itself hop to
    /// the main actor — the handler fires on an arbitrary queue.
    func startObserving(onChange: @escaping @Sendable () -> Void) {
        guard observerQueries.isEmpty else { return }
        let types: [HKSampleType] = [glucoseType, insulinType, carbType, HKObjectType.workoutType()]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                onChange()
                completion()
            }
            store.execute(query)
            observerQueries.append(query)
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
    func fetchInsulinSamples(since date: Date, limit: Int = 0) async throws -> [HealthInsulinSample] { [] }
    func fetchCarbSamples(since date: Date, limit: Int = 0) async throws -> [HealthCarbSample] { [] }
    func fetchWorkoutSamples(since date: Date, limit: Int = 0) async throws -> [HealthWorkoutSample] { [] }
    func enableBackgroundDelivery() async {}
    func startObserving(onChange: @escaping @Sendable () -> Void) {}
    func saveGlucose(mgdL: Double, at date: Date) async throws {}
    func saveInsulin(units: Double, isBasal: Bool, at date: Date) async throws {}
    func saveCarbs(grams: Double, at date: Date) async throws {}
    #endif
}
