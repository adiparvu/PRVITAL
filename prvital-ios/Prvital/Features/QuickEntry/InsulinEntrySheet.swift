import SwiftUI
import SwiftData

/// Create or edit an insulin dose, with the quick-dose chip row.
struct InsulinEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: InsulinDose?

    @State private var units: Double = 4
    @State private var timestamp = Date()
    @State private var type: InsulinType = .rapidActing
    @State private var name = ""
    @State private var delivery: InsulinDeliveryMethod = .pen
    @State private var context: InsulinDoseContext = .mealBolus
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
                    HStack {
                        Text("\(units.formatted()) U")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: units)
                        Spacer()
                        Stepper("", value: $units, in: 0...100, step: 0.5).labelsHidden()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(env.preferences.insulinPresets, id: \.self) { preset in
                                QuickChip(label: String(localized: "+\(preset.formatted()) U")) {
                                    units += preset; Haptics.play(.selection)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(InsulinType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Context", selection: $context) {
                        ForEach(InsulinDoseContext.allCases, id: \.self) { Text($0.label).tag($0) }
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
        }
    }

    private func load() {
        guard let existing else { return }
        units = existing.units
        timestamp = existing.timestamp
        type = existing.insulinType
        name = existing.insulinName ?? ""
        delivery = existing.deliveryMethod
        context = existing.doseContext
        note = existing.note ?? ""
        computeImpact(for: existing)
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
        if let existing {
            existing.units = units
            existing.timestamp = timestamp
            existing.insulinType = type
            existing.insulinName = name.isEmpty ? nil : name
            existing.deliveryMethod = delivery
            existing.doseContext = context
            existing.note = note.isEmpty ? nil : note
            env.entryStore.touch(existing)
        } else {
            env.entryStore.addInsulin(
                units: units, timestamp: timestamp, type: type,
                name: name.isEmpty ? nil : name, deliveryMethod: delivery,
                context: context, note: note.isEmpty ? nil : note
            )
        }
        Haptics.play(.success)
        dismiss()
    }
}
