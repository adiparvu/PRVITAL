import SwiftUI

/// Create or edit a glucose reading. Values are entered in the user's display
/// unit and stored canonically in mg/dL.
struct GlucoseEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: GlucoseReading?

    @State private var valueText = ""
    @State private var timestamp = Date()
    @State private var measurementType: GlucoseMeasurementType = .fingerstick
    @State private var trend: GlucoseTrend = .stable
    @State private var includeTrend = false
    @State private var selectedTags: Set<ObservationTag> = []

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Value", text: $valueText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(liveZoneColor)
                            .animation(.easeInOut(duration: 0.25), value: liveZoneColor)
                            .keyboardType(.decimalPad)
                        Text(unit.rawValue).foregroundStyle(Theme.textSecondary)
                    }
                    if let mgdL = enteredMgdL {
                        let zone = env.preferences.thresholds.zone(forMgdL: mgdL)
                        HStack { Text("Zone"); Spacer(); ZonePill(zone: zone) }
                    }
                }
                Section {
                    DatePicker("Time", selection: $timestamp)
                    Picker("Type", selection: $measurementType) {
                        ForEach(GlucoseMeasurementType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Add trend", isOn: $includeTrend.animation())
                    if includeTrend {
                        Picker("Trend", selection: $trend) {
                            ForEach(GlucoseTrend.allCases, id: \.self) {
                                Label($0.label, systemImage: $0.symbol).tag($0)
                            }
                        }
                    }
                }
                Section("Tags") {
                    EntryTagPicker(selected: $selectedTags)
                }
                if existing != nil { deleteSection }
            }
            .navigationTitle(existing == nil ? Text("Log glucose") : Text("Edit glucose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(enteredMgdL == nil) }
            }
            .onAppear(perform: load)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete", role: .destructive) {
                if let existing { env.entryStore.delete(existing) }
                Haptics.play(.warning)
                dismiss()
            }
        }
    }

    private var enteredMgdL: Double? {
        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return unit.toMgdL(value)
    }

    /// Tints the big value by its glucose zone as you type; neutral when empty.
    private var liveZoneColor: Color {
        guard let mgdL = enteredMgdL else { return Theme.textPrimary }
        return env.preferences.thresholds.zone(forMgdL: mgdL).color
    }

    private func load() {
        guard let existing else { return }
        valueText = GlucoseFormatting.string(mgdL: existing.valueMgdL, unit: unit)
        timestamp = existing.timestamp
        measurementType = existing.measurementType
        if let t = existing.trend { trend = t; includeTrend = true }
        selectedTags = Set(existing.tags)
    }

    private func save() {
        guard let mgdL = enteredMgdL else { return }
        if let existing {
            existing.valueMgdL = mgdL
            existing.timestamp = timestamp
            existing.measurementType = measurementType
            existing.trend = includeTrend ? trend : nil
            existing.tags = Array(selectedTags)
            env.entryStore.touch(existing)
        } else {
            let reading = env.entryStore.addGlucose(
                mgdL: mgdL, timestamp: timestamp,
                measurementType: measurementType,
                trend: includeTrend ? trend : nil
            )
            if !selectedTags.isEmpty {
                reading.tags = Array(selectedTags)
                env.entryStore.touch(reading)
            }
        }
        Haptics.play(.success)
        dismiss()
    }
}
