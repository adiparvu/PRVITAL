import SwiftUI

/// A searchable list for one therapy field: type to filter the 2026 catalog,
/// tap a suggestion, or keep exactly what you typed — free text is always
/// allowed. Writes back to the bound optional (nil when cleared).
struct TherapyCatalogPicker: View {
    let field: TherapyCatalog.Field
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [String] {
        TherapyCatalog.filter(field.options, query: query)
    }

    /// Offer a "use what I typed" row unless the text already matches an option.
    private var showFreeText: Bool {
        !trimmedQuery.isEmpty
            && !field.options.contains { $0.lowercased() == trimmedQuery.lowercased() }
    }

    var body: some View {
        List {
            if showFreeText {
                Section {
                    Button {
                        choose(trimmedQuery)
                    } label: {
                        Label {
                            Text("Use “\(trimmedQuery)”").foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "pencil").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .glassListRow()
            }

            Section {
                ForEach(filtered, id: \.self) { name in
                    Button {
                        choose(name)
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if isSelected(name) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Type to search, tap to choose, or keep exactly what you typed. Just a label for your records — never used to calculate doses.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            if selection?.isEmpty == false {
                Section {
                    Button("Clear", role: .destructive) {
                        Haptics.play(.light)
                        selection = nil
                        dismiss()
                    }
                }
                .glassListRow()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: field.searchPrompt)
    }

    private func isSelected(_ name: String) -> Bool {
        selection?.lowercased() == name.lowercased()
    }

    private func choose(_ value: String) {
        Haptics.play(.selection)
        selection = value
        dismiss()
    }
}
