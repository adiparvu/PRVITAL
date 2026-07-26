import SwiftUI

/// Adds or edits one medication schedule: name, type, dose, the daily times, and
/// whether reminders fire. Works on a local copy and hands the result back on
/// Save so the caller can persist it into the plan.
struct MedicationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var schedule: MedicationSchedule
    let isExisting: Bool
    let onSave: (MedicationSchedule) -> Void
    let onDelete: (MedicationSchedule) -> Void

    init(schedule: MedicationSchedule, isExisting: Bool,
         onSave: @escaping (MedicationSchedule) -> Void,
         onDelete: @escaping (MedicationSchedule) -> Void) {
        _schedule = State(initialValue: schedule)
        self.isExisting = isExisting
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let commonUnits = ["mg", "mcg", "g", "mL", "units", "tablet"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $schedule.name)
                    Picker("Type", selection: kindBinding) {
                        ForEach(MedicationKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    HStack {
                        Text("Dose")
                        Spacer()
                        TextField("0", value: $schedule.amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        TextField("Unit", text: $schedule.unitText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 70)
                            .foregroundStyle(Theme.accent)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonUnits, id: \.self) { unit in
                                Button(unit) { schedule.unitText = unit; Haptics.play(.selection) }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Theme.accentSoft, in: .capsule)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                } header: {
                    Text("Dose")
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(Array(schedule.times.enumerated()), id: \.offset) { index, _ in
                        DatePicker("Time", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                    }
                    .onDelete { schedule.times.remove(atOffsets: $0) }
                    Button {
                        Haptics.play(.selection)
                        schedule.times.append(defaultNewTime)
                    } label: {
                        Label("Add a time", systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Times")
                } footer: {
                    Text("The times of day you take this. Each one can send a reminder.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Reminders", isOn: $schedule.remindersEnabled)
                    Toggle("Active", isOn: $schedule.enabled)
                } footer: {
                    Text("Turn Active off to keep a medication in your list without reminders or adherence tracking.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                if isExisting {
                    Section {
                        Button(role: .destructive) {
                            Haptics.play(.warning)
                            onDelete(schedule)
                            dismiss()
                        } label: {
                            Label("Remove medication", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isExisting ? "Edit medication" : "New medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        schedule.name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        schedule.unitText = schedule.unitText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(schedule)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var kindBinding: Binding<MedicationKind> {
        Binding(get: { schedule.kind }, set: { schedule.kind = $0 })
    }

    /// A sensible time for a newly added slot: noon, or spread from the last one.
    private var defaultNewTime: Int {
        if let last = schedule.times.max() { return min(last + 4 * 60, 22 * 60) }
        return 8 * 60
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard schedule.times.indices.contains(index) else { return Date() }
                var c = DateComponents()
                c.hour = schedule.times[index] / 60
                c.minute = schedule.times[index] % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                guard schedule.times.indices.contains(index) else { return }
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule.times[index] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}
