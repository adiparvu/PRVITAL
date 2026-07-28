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
    /// Supplies the user's insulin duration of action, so a logged dose hands over
    /// to a correctly-sized "active insulin" countdown in the Dynamic Island.
    var insulinDurationHours: () -> Double = { BolusParameters.default.durationHours }

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
            reading.healthKitSyncedAt = timestamp
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
        mealTag: DoseMealTag? = nil,
        note: String? = nil,
        announces: Bool = true
    ) -> InsulinDose {
        let dose = InsulinDose(
            units: units, timestamp: timestamp, insulinType: type, insulinName: name,
            deliveryMethod: deliveryMethod, doseContext: doseContext, mealTag: mealTag,
            note: note
        )
        context.insert(dose)
        finish(.manualEdit, detail: "Insulin \(units) U logged")
        if healthKitEnabled {
            dose.healthKitSyncedAt = timestamp
            let hk = healthKit
            Task { try? await hk.saveInsulin(units: units, isBasal: type.isBasal, at: timestamp) }
        }
        // Flash the confirmation in the Dynamic Island, then hand over to the
        // active-insulin countdown. Only for a dose logged *now* — back-dating an
        // entry (or importing one) must not start a live countdown.
        if announces, Self.isLive(timestamp) {
            GlucoseLiveActivityManager.shared.presentInsulinLogged(
                units: units,
                clearsAt: timestamp.addingTimeInterval(insulinDurationHours() * 3600))
        }
        return dose
    }

    @discardableResult
    func addCarbs(
        grams: Double,
        timestamp: Date = Date(),
        mealType: MealType = .lunch,
        foodDescription: String? = nil,
        note: String? = nil,
        announces: Bool = true
    ) -> CarbEntry {
        let entry = CarbEntry(
            grams: grams, timestamp: timestamp, mealType: mealType,
            foodDescription: foodDescription, note: note
        )
        context.insert(entry)
        finish(.manualEdit, detail: "Carbs \(grams) g logged")
        if healthKitEnabled {
            entry.healthKitSyncedAt = timestamp
            let hk = healthKit
            Task { try? await hk.saveCarbs(grams: grams, at: timestamp) }
        }
        if announces, Self.isLive(timestamp) {
            GlucoseLiveActivityManager.shared.presentMealLogged(grams: grams)
        }
        return entry
    }

    /// Whether an entry is being logged "now" rather than back-dated or imported.
    /// Only a live entry earns a Dynamic Island confirmation.
    private static func isLive(_ timestamp: Date, now: Date = Date()) -> Bool {
        abs(now.timeIntervalSince(timestamp)) <= 15 * 60
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

    // MARK: Bulk import

    private static let importedNote = "Imported"
    /// How many records to insert between `save()`s during a large import, so a
    /// multi-year CGM history (100k+ rows) never does one giant blocking save.
    private static let importChunkSize = 2_000

    /// Imports many parsed rows efficiently and idempotently — the write path for
    /// CSV / Clarity / LibreView files, sized for a full multi-year export.
    ///
    /// Unlike the per-entry `add…` methods (which `save()`, audit and mirror to
    /// Health on every record), this:
    ///   • skips rows whose stable `externalID` already exists, so re-importing
    ///     the same file inserts nothing (glucose **and** insulin/carbs/activity),
    ///   • inserts in chunks with a single `save()` per chunk, yielding between
    ///     chunks so the UI stays responsive,
    ///   • resolves cross-source glucose duplicates once, over the recent window,
    ///   • writes a single summarising audit row.
    @discardableResult
    func bulkImport(
        _ rows: [ParsedRow],
        alreadySkipped: Int = 0,
        filename: String? = nil,
        formatName: String = "",
        progress: (@MainActor (Int, Int) -> Void)? = nil
    ) async -> ImportSummary {
        guard !rows.isEmpty else {
            return ImportSummary(imported: 0, skipped: alreadySkipped, duplicates: 0)
        }

        let timestamps = rows.map(\.timestamp)
        let minTS = timestamps.min() ?? .distantPast
        let maxTS = timestamps.max() ?? .distantFuture
        let existing = existingImportKeys(from: minTS, to: maxTS)
        let plan = BulkImportPlanner.plan(rows: rows, existing: existing)

        // Record this import as a batch so it can be listed and undone in one tap.
        // Every inserted record is stamped with the batch id.
        let batch = ImportBatch(filename: filename, formatName: formatName)
        context.insert(batch)
        let batchID = batch.id

        var inserted = 0
        var sinceSave = 0
        var didInsertGlucose = false

        for keyed in plan.toInsert {
            insertImported(keyed, batchID: batchID)
            switch keyed.row.record {
            case .glucose: batch.glucoseCount += 1; didInsertGlucose = true
            case .insulin: batch.insulinCount += 1
            case .carbs: batch.carbCount += 1
            case .activity: batch.activityCount += 1
            case .observation: batch.observationCount += 1
            }
            inserted += 1
            sinceSave += 1
            if sinceSave >= Self.importChunkSize {
                try? context.save()
                sinceSave = 0
                progress?(inserted, plan.toInsert.count)
                await Task.yield()
            }
        }
        batch.duplicateCount = plan.duplicates
        // An import that added nothing new (a re-import of the same file) leaves no
        // trace — drop the empty batch so the list only shows imports that landed.
        if inserted == 0 { context.delete(batch) }
        try? context.save()

        // Only the recent window can hold cross-source duplicates (Share /
        // Nightscout / HealthKit live data spans a few days); older imported
        // history has no other-source counterparts, so a full pass is wasted.
        if didInsertGlucose {
            resolveConflicts(since: Date().addingTimeInterval(-7 * 86_400))
        }

        audit.log(.manualEdit, source: nil, userConfirmation: true,
                  detail: "Imported \(inserted) record(s), \(plan.duplicates) duplicate(s) skipped")
        onChange()
        return ImportSummary(imported: inserted, skipped: alreadySkipped, duplicates: plan.duplicates)
    }

    /// Undoes an import: deletes every record stamped with the batch's id, then
    /// the batch itself. Used by the "Imported files" list so a wrong CSV can be
    /// removed cleanly without touching anything logged by hand or synced live.
    func deleteImportBatch(_ batch: ImportBatch) {
        let id = batch.id
        let total = batch.totalCount
        for r in (try? context.fetch(FetchDescriptor<GlucoseReading>(predicate: #Predicate { $0.importBatchID == id }))) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<InsulinDose>(predicate: #Predicate { $0.importBatchID == id }))) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<CarbEntry>(predicate: #Predicate { $0.importBatchID == id }))) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<ActivityEntry>(predicate: #Predicate { $0.importBatchID == id }))) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<ObservationEntry>(predicate: #Predicate { $0.importBatchID == id }))) ?? [] { context.delete(r) }
        context.delete(batch)
        try? context.save()
        audit.log(.dataDeletion, source: nil, userConfirmation: true,
                  detail: "Removed imported file (\(total) record(s))")
        onChange()
    }

    private func insertImported(_ keyed: KeyedImportRow, batchID: UUID) {
        let ts = keyed.row.timestamp
        let src = keyed.row.source
        switch keyed.row.record {
        case let .glucose(mgdL, measurement, trend):
            let reading = GlucoseReading(
                valueMgdL: mgdL, timestamp: ts, source: src,
                measurementType: measurement, trend: trend, externalID: keyed.externalID)
            reading.importBatchID = batchID
            context.insert(reading)
        case let .insulin(units, type, doseContext, name):
            let dose = InsulinDose(
                units: units, timestamp: ts, insulinType: type, insulinName: name,
                doseContext: doseContext, source: src, note: Self.importedNote)
            dose.externalID = keyed.externalID
            dose.importBatchID = batchID
            context.insert(dose)
        case let .carbs(grams, meal, food):
            let entry = CarbEntry(
                grams: grams, timestamp: ts, mealType: meal,
                foodDescription: food, source: src, note: Self.importedNote)
            entry.externalID = keyed.externalID
            entry.importBatchID = batchID
            context.insert(entry)
        case let .activity(type, minutes, intensity):
            let entry = ActivityEntry(
                activityType: type, startTimestamp: ts, durationSeconds: minutes * 60,
                intensity: intensity, source: src, note: Self.importedNote)
            entry.externalID = keyed.externalID
            entry.importBatchID = batchID
            context.insert(entry)
        case let .observation(tags, text):
            let entry = ObservationEntry(tags: tags, text: text, timestamp: ts, source: src)
            entry.externalID = keyed.externalID
            entry.importBatchID = batchID
            context.insert(entry)
        }
    }

    /// Collects the import-minted `externalID`s already stored across every
    /// record type within the incoming file's time range, so the planner can
    /// skip anything previously imported.
    private func existingImportKeys(from minTS: Date, to maxTS: Date) -> Set<String> {
        var keys = Set<String>()
        func add(_ ids: [String?]) {
            for case let id? in ids where id.hasPrefix(ImportKeys.prefix) { keys.insert(id) }
        }
        let g = FetchDescriptor<GlucoseReading>(predicate: #Predicate {
            $0.timestamp >= minTS && $0.timestamp <= maxTS && $0.externalID != nil })
        add(((try? context.fetch(g)) ?? []).map(\.externalID))
        let i = FetchDescriptor<InsulinDose>(predicate: #Predicate {
            $0.timestamp >= minTS && $0.timestamp <= maxTS && $0.externalID != nil })
        add(((try? context.fetch(i)) ?? []).map(\.externalID))
        let c = FetchDescriptor<CarbEntry>(predicate: #Predicate {
            $0.timestamp >= minTS && $0.timestamp <= maxTS && $0.externalID != nil })
        add(((try? context.fetch(c)) ?? []).map(\.externalID))
        let a = FetchDescriptor<ActivityEntry>(predicate: #Predicate {
            $0.timestamp >= minTS && $0.timestamp <= maxTS && $0.externalID != nil })
        add(((try? context.fetch(a)) ?? []).map(\.externalID))
        let o = FetchDescriptor<ObservationEntry>(predicate: #Predicate {
            $0.timestamp >= minTS && $0.timestamp <= maxTS && $0.externalID != nil })
        add(((try? context.fetch(o)) ?? []).map(\.externalID))
        return keys
    }

    /// One-time repair for readings hidden by the old conflict order.
    ///
    /// Until build 184 the resolver compared source priority before
    /// measurement-type authority, so a finger-stick logged while a CGM was
    /// streaming lost to the sensor sample beside it and was marked inactive —
    /// invisible in the journal, the statistics and the charts. Re-resolving
    /// their clusters with the corrected order brings every one of them back.
    ///
    /// Bounded and idempotent: only superseded finger-stick / lab readings are
    /// fetched (a handful even for a heavy logger), each cluster is re-run
    /// once, and the flag makes it a no-op afterwards.
    func repairSupersededBloodReadingsOnce() {
        let flagKey = "entryStore.didRepairSupersededBloodReadings"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)

        let fingerstick = GlucoseMeasurementType.fingerstick.rawValue
        let laboratory = GlucoseMeasurementType.laboratory.rawValue
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate {
                $0.isActive == false
                && ($0.measurementTypeRaw == fingerstick || $0.measurementTypeRaw == laboratory)
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let hidden = try? context.fetch(descriptor), !hidden.isEmpty else { return }

        // One pass per cluster: walk the affected timestamps and skip any that
        // an earlier pass already covered.
        var lastResolvedUpTo: Date?
        var repaired = 0
        for reading in hidden {
            if let lastResolvedUpTo, reading.timestamp <= lastResolvedUpTo { continue }
            resolveConflicts(around: reading.timestamp)
            lastResolvedUpTo = reading.timestamp.addingTimeInterval(600)
            repaired += 1
        }
        try? context.save()
        audit.log(.manualEdit, userConfirmation: false,
                  detail: "Restored \(hidden.count) superseded blood readings across \(repaired) clusters")
        onChange()
    }

    /// Re-runs conflict resolution over every reading since `date` (one pass).
    private func resolveConflicts(since date: Date) {
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let readings = try? context.fetch(descriptor) else { return }
        ConflictResolver(sourcePriority: registry.sourcePriority).resolve(readings)
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
        remirrorToHealth(record)
        finish(.manualEdit, source: record.source, detail: "\(record.recordType.rawValue) edited")
    }

    func delete<T: PersistentModel>(_ record: T) {
        let source = (record as? any MedicalRecord)?.source
        // Capture the timestamp before deletion so we can re-resolve the reading's
        // conflict cluster afterwards — otherwise deleting the *active* member of a
        // duplicate group leaves the others stuck inactive and that instant
        // disappears from every stats/chart path.
        let glucoseTimestamp = (record as? GlucoseReading)?.timestamp
        unmirrorFromHealth(record)
        context.delete(record)
        if let glucoseTimestamp {
            resolveConflicts(around: glucoseTimestamp)
        }
        finish(.dataDeletion, source: source, detail: "Record deleted")
    }

    /// An edit propagates to Apple Health as delete-then-rewrite: the old
    /// sample is found at `healthKitSyncedAt` (where the last mirror put it —
    /// robust even when the edit changed the entry's time), and the current
    /// values are written fresh. Manual entries only; imported data is never
    /// mirrored back.
    private func remirrorToHealth<T: PersistentModel>(_ record: T) {
        guard healthKitEnabled else { return }
        let hk = healthKit
        if let reading = record as? GlucoseReading, reading.source == .manual {
            let old = reading.healthKitSyncedAt
            let (mgdL, at) = (reading.valueMgdL, reading.timestamp)
            reading.healthKitSyncedAt = at
            Task {
                if let old { await hk.deleteOwnSamples(.glucose, at: old) }
                try? await hk.saveGlucose(mgdL: mgdL, at: at)
            }
        } else if let entry = record as? CarbEntry, entry.source == .manual {
            let old = entry.healthKitSyncedAt
            let (grams, at) = (entry.grams, entry.timestamp)
            entry.healthKitSyncedAt = at
            Task {
                if let old { await hk.deleteOwnSamples(.carbs, at: old) }
                try? await hk.saveCarbs(grams: grams, at: at)
            }
        } else if let dose = record as? InsulinDose, dose.source == .manual {
            let old = dose.healthKitSyncedAt
            let (units, isBasal, at) = (dose.units, dose.insulinType.isBasal, dose.timestamp)
            dose.healthKitSyncedAt = at
            Task {
                if let old { await hk.deleteOwnSamples(.insulin, at: old) }
                try? await hk.saveInsulin(units: units, isBasal: isBasal, at: at)
            }
        }
    }

    /// A delete removes the mirrored Health sample too (our own source only).
    private func unmirrorFromHealth<T: PersistentModel>(_ record: T) {
        guard healthKitEnabled else { return }
        let hk = healthKit
        if let reading = record as? GlucoseReading, let at = reading.healthKitSyncedAt {
            Task { await hk.deleteOwnSamples(.glucose, at: at) }
        } else if let entry = record as? CarbEntry, let at = entry.healthKitSyncedAt {
            Task { await hk.deleteOwnSamples(.carbs, at: at) }
        } else if let dose = record as? InsulinDose, let at = dose.healthKitSyncedAt {
            Task { await hk.deleteOwnSamples(.insulin, at: at) }
        }
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
