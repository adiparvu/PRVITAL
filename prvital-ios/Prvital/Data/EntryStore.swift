import Foundation
import SwiftData

/// The single write path for every medical record.
///
/// Centralising mutation here means each add / edit / delete consistently:
///   • persists to SwiftData,
///   • writes an audit row (manual edit / deletion),
///   • mirrors to Apple Health when the user has consented,
///   • re-runs conflict resolution around new glucose, and
///   • refreshes the widgets/watch snapshot.
@MainActor
final class EntryStore {
    private let context: ModelContext
    private let audit: AuditService
    private let healthKit: HealthKitService
    private let consent: ConsentStore
    private let registry: SourceRegistry
    /// Called after any change so the environment can republish the snapshot.
    var onChange: () -> Void = {}

    init(
        context: ModelContext,
        audit: AuditService,
        healthKit: HealthKitService,
        consent: ConsentStore,
        registry: SourceRegistry
    ) {
        self.context = context
        self.audit = audit
        self.healthKit = healthKit
        self.consent = consent
        self.registry = registry
    }

    private var healthKitEnabled: Bool { consent.isGranted(.healthKit) }

    // MARK: Create

    @discardableResult
    func addGlucose(
        mgdL: Double,
        timestamp: Date = Date(),
        measurementType: GlucoseMeasurementType = .manual,
        trend: GlucoseTrend? = nil,
        source: DataSource = .manual
    ) -> GlucoseReading {
        let reading = GlucoseReading(
            valueMgdL: mgdL, timestamp: timestamp, source: source,
            measurementType: measurementType, trend: trend
        )
        context.insert(reading)
        resolveConflicts(around: timestamp)
        finish(.manualEdit, source: source, detail: "Glucose logged")
        if healthKitEnabled, source == .manual {
            let hk = healthKit
            Task { try? await hk.saveGlucose(mgdL: mgdL, at: timestamp) }
        }
        return reading
    }

    @discardableResult
    func addInsulin(
        units: Double,
        timestamp: Date = Date(),
        type: InsulinType = .rapidActing,
        name: String? = nil,
        deliveryMethod: InsulinDeliveryMethod = .pen,
        context doseContext: InsulinDoseContext = .mealBolus,
        note: String? = nil
    ) -> InsulinDose {
        let dose = InsulinDose(
            units: units, timestamp: timestamp, insulinType: type, insulinName: name,
            deliveryMethod: deliveryMethod, doseContext: doseContext, note: note
        )
        context.insert(dose)
        finish(.manualEdit, detail: "Insulin \(units) U logged")
        if healthKitEnabled {
            let hk = healthKit
            Task { try? await hk.saveInsulin(units: units, isBasal: type.isBasal, at: timestamp) }
        }
        return dose
    }

    @discardableResult
    func addCarbs(
        grams: Double,
        timestamp: Date = Date(),
        mealType: MealType = .lunch,
        foodDescription: String? = nil,
        note: String? = nil
    ) -> CarbEntry {
        let entry = CarbEntry(
            grams: grams, timestamp: timestamp, mealType: mealType,
            foodDescription: foodDescription, note: note
        )
        context.insert(entry)
        finish(.manualEdit, detail: "Carbs \(grams) g logged")
        if healthKitEnabled {
            let hk = healthKit
            Task { try? await hk.saveCarbs(grams: grams, at: timestamp) }
        }
        return entry
    }

    @discardableResult
    func addActivity(
        type: ActivityType,
        start: Date = Date(),
        durationSeconds: Int,
        intensity: ActivityIntensity = .moderate,
        caloriesBurned: Double? = nil,
        distanceMeters: Double? = nil,
        note: String? = nil
    ) -> ActivityEntry {
        let entry = ActivityEntry(
            activityType: type, startTimestamp: start, durationSeconds: durationSeconds,
            intensity: intensity, caloriesBurned: caloriesBurned,
            distanceMeters: distanceMeters, note: note
        )
        context.insert(entry)
        finish(.manualEdit, detail: "Activity logged")
        return entry
    }

    @discardableResult
    func addObservation(tags: [ObservationTag], text: String?, timestamp: Date = Date()) -> ObservationEntry {
        let entry = ObservationEntry(tags: tags, text: text, timestamp: timestamp)
        context.insert(entry)
        finish(.manualEdit, detail: "Observation logged")
        return entry
    }

    @discardableResult
    func addMedication(
        name: String,
        kind: MedicationKind = .other,
        amount: Double = 0,
        unitText: String = "",
        timestamp: Date = Date(),
        scheduleID: String? = nil,
        note: String? = nil
    ) -> MedicationDose {
        let dose = MedicationDose(
            name: name, kind: kind, amount: amount, unitText: unitText,
            timestamp: timestamp, scheduleID: scheduleID, note: note)
        context.insert(dose)
        finish(.manualEdit, detail: "Medication logged")
        return dose
    }

    // MARK: Food library

    /// Inserts a food into the local library if it isn't already there (matched
    /// by barcode), returning the stored instance.
    @discardableResult
    func saveFood(_ food: FoodItem) -> FoodItem {
        if let existing = existingFood(matching: food) { return existing }
        context.insert(food)
        finish(.manualEdit, detail: "Food \"\(food.name)\" saved")
        return food
    }

    /// Logs a carbohydrate entry for a portion of a food: saves the food to the
    /// library, bumps its use count, computes the carbs for the portion and
    /// records the entry through the normal carb path.
    @discardableResult
    func logFood(
        _ food: FoodItem,
        portionGrams: Double,
        mealType: MealType = .lunch,
        timestamp: Date = Date(),
        useNetCarbs: Bool = false,
        note: String? = nil
    ) -> CarbEntry {
        let stored = saveFood(food)
        stored.useCount += 1
        stored.lastUsedAt = timestamp
        stored.updatedAt = Date()

        let carbs = CarbCalculator.carbs(
            portionGrams: portionGrams,
            carbsPer100g: stored.carbsPer100g,
            fiberPer100g: stored.fiberPer100g,
            useNetCarbs: useNetCarbs
        )
        let grams = (carbs * 10).rounded() / 10
        let portion = portionGrams.formatted(.number.precision(.fractionLength(0)))
        return addCarbs(
            grams: grams,
            timestamp: timestamp,
            mealType: mealType,
            foodDescription: "\(stored.name) · \(portion) g",
            note: note
        )
    }

    private func existingFood(matching food: FoodItem) -> FoodItem? {
        if food.modelContext != nil { return food } // already stored
        guard let barcode = food.barcode, !barcode.isEmpty else { return nil }
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == barcode })
        return try? context.fetch(descriptor).first
    }

    // MARK: Sensor sessions

    /// Records the start of a new sensor wear session.
    @discardableResult
    func startSensorSession(kind: SensorKind, start: Date = Date()) -> SensorSession {
        let session = SensorSession(startDate: start, kind: kind)
        context.insert(session)
        finish(.manualEdit, detail: "Sensor session started (\(kind.displayName))")
        return session
    }

    // MARK: Update / Delete

    func touch<T: PersistentModel & MedicalRecord>(_ record: T) {
        record.updatedAt = Date()
        if let glucose = record as? GlucoseReading {
            resolveConflicts(around: glucose.timestamp)
        }
        finish(.manualEdit, source: record.source, detail: "\(record.recordType.rawValue) edited")
    }

    func delete<T: PersistentModel>(_ record: T) {
        let source = (record as? any MedicalRecord)?.source
        // Capture the timestamp before deletion so we can re-resolve the reading's
        // conflict cluster afterwards — otherwise deleting the *active* member of a
        // duplicate group leaves the others stuck inactive and that instant
        // disappears from every stats/chart path.
        let glucoseTimestamp = (record as? GlucoseReading)?.timestamp
        context.delete(record)
        if let glucoseTimestamp {
            resolveConflicts(around: glucoseTimestamp)
        }
        finish(.dataDeletion, source: source, detail: "Record deleted")
    }

    // MARK: Internals

    private func resolveConflicts(around date: Date) {
        let lower = date.addingTimeInterval(-600)
        let upper = date.addingTimeInterval(600)
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let readings = try? context.fetch(descriptor) else { return }
        ConflictResolver(sourcePriority: registry.sourcePriority).resolve(readings)
    }

    private func finish(_ action: AuditActionType, source: DataSource? = nil, detail: String) {
        try? context.save()
        audit.log(action, source: source, userConfirmation: true, detail: detail)
        onChange()
    }
}
