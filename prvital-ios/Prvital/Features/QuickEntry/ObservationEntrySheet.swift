import SwiftUI

/// Create or edit a contextual observation (illness, stress, sleep…).
struct ObservationEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: ObservationEntry?

    @State private var selected: Set<ObservationTag> = []
    @State private var text = ""
    @State private var timestamp = Date()

    /// Two equal columns: the adaptive grid packed three uneven cells per row
    /// and broke the longer Romanian labels mid-word (device feedback).
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

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
                                // Leading-aligned, one line, gently scaled —
                                // every cell the same height, nothing wraps.
                                HStack(spacing: 8) {
                                    Image(systemName: tag.symbol)
                                        .font(.footnote.weight(.medium))
                                        .frame(width: 18)
                                    Text(tag.label)
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Spacer(minLength: 0)
                                    if isOn {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .frame(maxWidth: .infinity)
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
