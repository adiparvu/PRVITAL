import SwiftUI

/// Create or edit a contextual observation (illness, stress, sleep…).
struct ObservationEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: ObservationEntry?

    @State private var selected: Set<ObservationTag> = []
    @State private var text = ""
    @State private var timestamp = Date()

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Tags") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(ObservationTag.allCases) { tag in
                            let isOn = selected.contains(tag)
                            Button {
                                if isOn { selected.remove(tag) } else { selected.insert(tag) }
                                Haptics.play(.selection)
                            } label: {
                                Label(tag.label, systemImage: tag.symbol)
                                    .font(.footnote.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isOn ? Theme.accent.opacity(0.18) : Theme.hairline.opacity(0.4), in: .rect(cornerRadius: 12))
                                    .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
                                    .animation(.snappy(duration: 0.2), value: isOn)
                            }
                            .buttonStyle(PressableChipStyle())
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section("Note") { TextField("Optional", text: $text, axis: .vertical) }
                Section { DatePicker("Time", selection: $timestamp) }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing { env.entryStore.delete(existing) }
                            Haptics.play(.warning); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? Text("Add observation") : Text("Edit observation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(selected.isEmpty && text.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing else { return }
        selected = Set(existing.tags)
        text = existing.text ?? ""
        timestamp = existing.timestamp
    }

    private func save() {
        let tags = Array(selected)
        if let existing {
            existing.tags = tags
            existing.text = text.isEmpty ? nil : text
            existing.timestamp = timestamp
            env.entryStore.touch(existing)
        } else {
            env.entryStore.addObservation(tags: tags, text: text.isEmpty ? nil : text, timestamp: timestamp)
        }
        Haptics.play(.success)
        dismiss()
    }
}
