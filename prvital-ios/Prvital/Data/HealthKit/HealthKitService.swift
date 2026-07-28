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

/// A Sendable projection of an Apple Health heart-rate sample (beats per minute),
/// used to overlay heart rate against glucose on the activity chart.
struct HeartRateSample: Sendable, Identifiable {
    let id: String
    let bpm: Double
    let timestamp: Date
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
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    // Wellness metrics for the Health hub (all read-only; never written back).
    var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    var exerciseType: HKQuantityType { HKQuantityType(.appleExerciseTime) }
    var restingHRType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    var respiratoryType: HKQuantityType { HKQuantityType(.respiratoryRate) }
    var oxygenType: HKQuantityType { HKQuantityType(.oxygenSaturation) }
    var systolicType: HKQuantityType { HKQuantityType(.bloodPressureSystolic) }
    var diastolicType: HKQuantityType { HKQuantityType(.bloodPressureDiastolic) }
    var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    private var shareTypes: Set<HKSampleType> {
        [glucoseType, insulinType, carbType, HKObjectType.workoutType()]
    }
    private var readTypes: Set<HKObjectType> {
        // Heart rate + the wellness metrics are read-only (for the Health hub and
        // the activity chart); never written back.
        [glucoseType, insulinType, carbType, heartRateType, HKObjectType.workoutType(),
         stepType, activeEnergyType, exerciseType, restingHRType, hrvType,
         respiratoryType, oxygenType, systolicType, diastolicType, bodyMassType, sleepType]
    }

    /// Persisted marker that the user completed the Health connection flow at
    /// least once. iOS deliberately hides READ authorization from apps, so
    /// this flag is the only way the Sources screen can remember "connected"
    /// across launches — without it Apple Health showed as disconnected on
    /// every new session (device bug report).
    static let connectedFlagKey = "source.healthKit.connected"

    func requestAuthorization() async throws {
        guard isAvailable else { throw SourceError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        (UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard)
            .set(true, forKey: Self.connectedFlagKey)
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

    /// Heart-rate samples within a window (ascending by time), for overlaying HR
    /// against glucose on the activity chart. Read-only from Apple Health.
    func fetchHeartRateSamples(from start: Date, to end: Date, limit: Int = 3000) async throws -> [HeartRateSample] {
        let samples = try await quantitySamplesWindowed(of: heartRateType, from: start, to: end, limit: limit)
        return samples
            .map { HeartRateSample(id: $0.uuid.uuidString,
                                   bpm: $0.quantity.doubleValue(for: bpmUnit),
                                   timestamp: $0.startDate) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func quantitySamplesWindowed(of type: HKQuantityType, from start: Date, to end: Date, limit: Int) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: SourceError.underlying(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: Health hub — wellness metrics

    /// (type, unit, statistics option) for a quantity-based metric. Blood pressure
    /// and sleep are aggregated separately.
    private func quantityConfig(for kind: HealthMetricKind) -> (HKQuantityType, HKUnit, HKStatisticsOptions)? {
        switch kind {
        case .steps:            return (stepType, .count(), .cumulativeSum)
        case .activeEnergy:     return (activeEnergyType, .kilocalorie(), .cumulativeSum)
        case .exercise:         return (exerciseType, .minute(), .cumulativeSum)
        case .restingHeartRate: return (restingHRType, bpmUnit, .discreteAverage)
        case .hrv:              return (hrvType, HKUnit.secondUnit(with: .milli), .discreteAverage)
        case .respiratoryRate:  return (respiratoryType, bpmUnit, .discreteAverage)
        case .oxygen:           return (oxygenType, .percent(), .discreteAverage)
        case .weight:           return (bodyMassType, .gramUnit(with: .kilo), .discreteAverage)
        case .bloodPressure, .sleep: return nil
        }
    }

    /// Daily buckets for a quantity metric over the last `days`, via a statistics
    /// collection query — HealthKit aggregates each day server-side, so the app
    /// never materialises thousands of raw samples on the main thread.
    func dailyMetric(_ kind: HealthMetricKind, days: Int) async -> [DailyMetric] {
        guard isAvailable, let (type, unit, option) = quantityConfig(for: kind) else { return [] }
        let cal = Calendar.current
        let end = Date()
        let anchor = cal.startOfDay(for: end)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: option, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var out: [DailyMetric] = []
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let q = option == .cumulativeSum ? stat.sumQuantity() : stat.averageQuantity()
                    if let q { out.append(DailyMetric(day: stat.startDate, value: q.doubleValue(for: unit))) }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// The most recent reading of a quantity metric (resting HR, HRV, SpO2, weight…).
    func latestReading(_ kind: HealthMetricKind) async -> MetricReading? {
        guard isAvailable, let (type, unit, _) = quantityConfig(for: kind) else { return nil }
        let samples = try? await quantitySamples(of: type, since: .distantPast, limit: 1)
        guard let s = samples?.first else { return nil }
        return MetricReading(value: s.quantity.doubleValue(for: unit), date: s.startDate)
    }

    /// The latest blood-pressure pair (systolic + diastolic).
    func latestBloodPressure() async -> BloodPressureReading? {
        guard isAvailable else { return nil }
        let sys = try? await quantitySamples(of: systolicType, since: .distantPast, limit: 1)
        let dia = try? await quantitySamples(of: diastolicType, since: .distantPast, limit: 1)
        guard let s = sys?.first, let d = dia?.first else { return nil }
        let mmHg = HKUnit.millimeterOfMercury()
        return BloodPressureReading(systolic: s.quantity.doubleValue(for: mmHg),
                                    diastolic: d.quantity.doubleValue(for: mmHg),
                                    date: s.startDate)
    }

    /// Hours asleep per night over the last `days`, bucketed to each interval's day.
    func sleepHoursByNight(days: Int) async -> [DailyMetric] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let asleep: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        var byDay: [Date: Double] = [:]
        for s in asleep where asleepValues.contains(s.value) {
            let day = cal.startOfDay(for: s.startDate)
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        return byDay.map { DailyMetric(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }

    /// A bucketed series plus summary figures (average / lowest / highest) for a
    /// metric over one interval — the data behind the per-metric detail screen.
    /// Hourly buckets for a day, daily for a week or month, monthly for a year.
    /// For level metrics (heart rate, HRV…) the min/max are the true sample
    /// extremes, so the summary matches Apple Health rather than the min/max of
    /// the daily averages.
    func metricSeries(_ kind: HealthMetricKind, interval: MetricInterval) async -> MetricSeries {
        guard isAvailable else { return .empty }
        if kind == .sleep { return await sleepSeries(interval: interval) }
        guard let (type, unit, option) = quantityConfig(for: kind) else { return .empty }

        let cal = Calendar.current
        let end = Date()
        let anchor: Date
        let comps: DateComponents
        switch interval {
        case .day:
            anchor = cal.startOfDay(for: end); comps = DateComponents(hour: 1)
        case .week:
            anchor = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: end)) ?? end
            comps = DateComponents(day: 1)
        case .month:
            anchor = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: end)) ?? end
            comps = DateComponents(day: 1)
        case .year:
            let startMonth = cal.date(byAdding: .month, value: -11, to: cal.startOfDay(for: end)) ?? end
            anchor = cal.dateInterval(of: .month, for: startMonth)?.start ?? startMonth
            comps = DateComponents(month: 1)
        }

        var options = option
        if option == .discreteAverage { options.insert(.discreteMin); options.insert(.discreteMax) }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: options, anchorDate: anchor, intervalComponents: comps)
            query.initialResultsHandler = { _, results, _ in
                var points: [DailyMetric] = []
                var lo = Double.greatestFiniteMagnitude
                var hi = -Double.greatestFiniteMagnitude
                var sum = 0.0
                var n = 0
                results?.enumerateStatistics(from: anchor, to: end) { stat, _ in
                    if option == .cumulativeSum {
                        guard let q = stat.sumQuantity() else { return }
                        let v = q.doubleValue(for: unit)
                        points.append(DailyMetric(day: stat.startDate, value: v))
                        lo = min(lo, v); hi = max(hi, v); sum += v; n += 1
                    } else {
                        guard let avg = stat.averageQuantity() else { return }
                        let v = avg.doubleValue(for: unit)
                        points.append(DailyMetric(day: stat.startDate, value: v))
                        sum += v; n += 1
                        if let mn = stat.minimumQuantity() { lo = min(lo, mn.doubleValue(for: unit)) }
                        if let mx = stat.maximumQuantity() { hi = max(hi, mx.doubleValue(for: unit)) }
                    }
                }
                guard n > 0 else { continuation.resume(returning: .empty); return }
                if lo > hi { lo = 0; hi = 0 }
                continuation.resume(returning: MetricSeries(
                    points: points, average: sum / Double(n), minimum: lo, maximum: hi))
            }
            store.execute(query)
        }
    }

    private func sleepSeries(interval: MetricInterval) async -> MetricSeries {
        let days: Int
        switch interval {
        case .day: days = 1
        case .week: days = 7
        case .month: days = 30
        case .year: days = 365
        }
        let nights = await sleepHoursByNight(days: days)
        guard !nights.isEmpty else { return .empty }
        let values = nights.map(\.value)
        return MetricSeries(points: nights,
                            average: values.reduce(0, +) / Double(values.count),
                            minimum: values.min() ?? 0,
                            maximum: values.max() ?? 0)
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

    /// The record kinds the app mirrors into Health (and may need to unmirror).
    enum WriteKind: Sendable { case glucose, insulin, carbs }

    /// Deletes the sample(s) THIS APP wrote at the given instant — how an edit
    /// or delete in Prvital propagates. Scoped to our own source and a ±1 s
    /// window around the mirrored timestamp, so another app's data at the same
    /// moment is never touched.
    func deleteOwnSamples(_ kind: WriteKind, at date: Date) async {
        let type: HKQuantityType
        switch kind {
        case .glucose: type = glucoseType
        case .insulin: type = insulinType
        case .carbs: type = carbType
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1),
                                        end: date.addingTimeInterval(1),
                                        options: []),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        _ = try? await store.deleteObjects(of: type, predicate: predicate)
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
    enum WriteKind: Sendable { case glucose, insulin, carbs }
    func deleteOwnSamples(_ kind: WriteKind, at date: Date) async {}
    func dailyMetric(_ kind: HealthMetricKind, days: Int) async -> [DailyMetric] { [] }
    func latestReading(_ kind: HealthMetricKind) async -> MetricReading? { nil }
    func latestBloodPressure() async -> BloodPressureReading? { nil }
    func sleepHoursByNight(days: Int) async -> [DailyMetric] { [] }
    func metricSeries(_ kind: HealthMetricKind, interval: MetricInterval) async -> MetricSeries { .empty }
    #endif
}
