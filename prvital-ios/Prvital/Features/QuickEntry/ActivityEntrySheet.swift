import SwiftUI

/// Create or edit a physical-activity session.
struct ActivityEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: ActivityEntry?

    @State private var type: ActivityType = .walking
    @State private var start = Date()
    @State private var minutes = 30
    @State private var intensity: ActivityIntensity = .moderate
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $type) {
                        ForEach(ActivityType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Intensity", selection: $intensity) {
                        ForEach(ActivityIntensity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("Duration") {
                    Text("\(minutes) min")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.zoneInRange)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: minutes)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(env.preferences.activityDurations, id: \.self) { duration in
                                QuickChip(label: "\(duration)", isSelected: minutes == duration, tint: Theme.accent) {
                                    minutes = duration; Haptics.play(.selection)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                Section {
                    DatePicker("Start", selection: $start)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing { env.entryStore.delete(existing) }
                            Haptics.play(.warning); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Log activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing else { return }
        type = existing.activityType
        start = existing.startTimestamp
        minutes = max(1, existing.durationMinutes)
        intensity = existing.intensity
        note = existing.note ?? ""
    }

    private func save() {
        if let existing {
            existing.activityType = type
            existing.startTimestamp = start
            existing.timestamp = start
            existing.durationSeconds = minutes * 60
            existing.endTimestamp = start.addingTimeInterval(TimeInterval(minutes * 60))
            existing.intensity = intensity
            existing.note = note.isEmpty ? nil : note
            env.entryStore.touch(existing)
        } else {
            env.entryStore.addActivity(
                type: type, start: start, durationSeconds: minutes * 60,
                intensity: intensity, note: note.isEmpty ? nil : note
            )
        }
        Haptics.play(.success)
        dismiss()
    }
}
