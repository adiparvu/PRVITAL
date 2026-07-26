import SwiftUI
import SwiftData

/// Create or edit an insulin dose, with the quick-dose chip row.
struct InsulinEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: InsulinDose?

    @State private var units: Double = 0
    @State private var timestamp = Date()
    @State private var type: InsulinType = .rapidActing
    @State private var name = ""
    @State private var delivery: InsulinDeliveryMethod = .pen
    @State private var context: InsulinDoseContext = .mealBolus
    @State private var mealTag: DoseMealTag?
    @State private var note = ""
    /// The connected glucose story for an existing dose (before → after + IOB).
    @State private var impact: EventInsight?

    var body: some View {
        NavigationStack {
            Form {
                if let impact, impact.hasContext {
                    Section("Impact") {
                        EventImpactSection(insight: impact,
                                           unit: env.preferences.glucoseUnit,
                                           thresholds: env.preferences.thresholds)
                    }
                }
                Section {
                    // Just the box — you type the dose (device feedback: no
                    // stepper, no preset chips here).
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", value: $units, format: .number)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .keyboardType(.decimalPad)
                            .fixedSize()
                            .accessibilityLabel("Insulin units")
                        Text("U")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .onChange(of: units) { _, value in
                        if value < 0 { units = 0 } else if value > 100 { units = 100 }
                    }
                }
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(InsulinType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Context", selection: $context) {
                        ForEach(InsulinDoseContext.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    // "For: breakfast / lunch / dinner / snack" — the register
                    // trusts this word over any time-window guess. Only a meal
                    // bolus carries it; corrections/basal never join a meal.
                    if context == .mealBolus {
                        Picker("For", selection: $mealTag) {
                            Text("Automatic").tag(DoseMealTag?.none)
                            ForEach(DoseMealTag.allCases, id: \.self) {
                                Text($0.label).tag(Optional($0))
                            }
                        }
                    }
                    Picker("Delivery", selection: $delivery) {
                        ForEach(InsulinDeliveryMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Insulin name (optional)", text: $name)
                    DatePicker("Time", selection: $timestamp)
                }
                Section("Note") { TextField("Optional", text: $note, axis: .vertical) }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing { env.entryStore.delete(existing) }
                            Haptics.play(.warning); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? Text("Log insulin") : Text("Edit insulin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(units <= 0) }
            }
            .onAppear(perform: load)
            // Keep the name in step with the chosen type, but never overwrite
            // something the user typed themselves: swap only while the field is
            // empty or still holding one of the profile's two presets.
            .onChange(of: type) { _, _ in
                let profile = env.profile.current()
                let presets = [profile.bolusInsulinName, profile.basalInsulinName]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                if name.isEmpty || presets.contains(name) {
                    name = presetName ?? ""
                }
            }
        }
    }

    /// The insulin this person already told the app they use (Profile →
    /// My therapy), matched to the selected type — so logging a dose starts
    /// with the right name filled in instead of an empty optional field.
    private var presetName: String? {
        let profile = env.profile.current()
        switch type {
        case .rapidActing:
            return profile.bolusInsulinName
        case .longActing, .intermediate:
            return profile.basalInsulinName
        case .premixed:
            return nil
        }
    }

    private func load() {
        guard let existing else {
            // A fresh dose starts with the profile's preset for the type and a
            // meal suggestion from the clock — one glance to confirm, one tap
            // to correct, and the register gets the user's explicit word.
            if name.isEmpty, let preset = presetName, !preset.isEmpty {
                name = preset
            }
            mealTag = Self.suggestedMealTag(for: timestamp)
            return
        }
        units = existing.units
        timestamp = existing.timestamp
        type = existing.insulinType
        name = existing.insulinName ?? ""
        delivery = existing.deliveryMethod
        context = existing.doseContext
        mealTag = existing.mealTag
        note = existing.note ?? ""
        computeImpact(for: existing)
    }

    /// The meal a dose at this hour is most likely for, using the same time
    /// bands the register's fallback anchors use (04–11 / 11–16 / 16–22).
    static func suggestedMealTag(for date: Date) -> DoseMealTag {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    /// Reads the glucose around this dose and the insulin already active at its
    /// time, so the editor can show the connected before → after + IOB story.
    private func computeImpact(for dose: InsulinDose) {
        let event = dose.timestamp
        let lo = event.addingTimeInterval(-60 * 60)
        let hi = event.addingTimeInterval(4 * 3600)
        let gDesc = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= lo && $0.timestamp <= hi },
            sortBy: [SortDescriptor(\.timestamp)])
        let readings = (try? env.modelContainer.mainContext.fetch(gDesc)) ?? []
        let diaLo = event.addingTimeInterval(-env.preferences.bolusParameters.durationHours * 3600)
        let iDesc = FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= diaLo && $0.timestamp <= event },
            sortBy: [SortDescriptor(\.timestamp)])
        let doses = (try? env.modelContainer.mainContext.fetch(iDesc)) ?? []
        impact = EventInsight.make(
            eventDate: event, excludingDoseID: dose.id,
            readings: readings, insulin: doses,
            bolus: env.preferences.bolusParameters)
    }

    private func save() {
        // The meal word only makes sense on a meal bolus.
        let tag = context == .mealBolus ? mealTag : nil
        if let existing {
            existing.units = units
            existing.timestamp = timestamp
            existing.insulinType = type
            existing.insulinName = name.isEmpty ? nil : name
            existing.deliveryMethod = delivery
            existing.doseContext = context
            existing.mealTag = tag
            existing.note = note.isEmpty ? nil : note
            env.entryStore.touch(existing)
        } else {
            env.entryStore.addInsulin(
                units: units, timestamp: timestamp, type: type,
                name: name.isEmpty ? nil : name, deliveryMethod: delivery,
                context: context, mealTag: tag, note: note.isEmpty ? nil : note
            )
        }
        Haptics.play(.success)
        dismiss()
    }
}
