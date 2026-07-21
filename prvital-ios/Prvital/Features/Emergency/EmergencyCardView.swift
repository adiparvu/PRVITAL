import SwiftUI

/// The emergency "medical card": a bold, high-contrast screen the user can show —
/// or a stranger can be handed — during severe hypoglycemia. It leads with the
/// one fact that matters ("I have diabetes"), gives a bystander three simple
/// steps, and then shows whatever the user has filled in: where their glucagon
/// is kept, notes for a helper, and contacts as tappable call buttons.
///
/// This is bystander guidance, not medical dosing — the framing is always
/// "give sugar, use my glucagon, call emergency services".
struct EmergencyCardView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var showEditor = false

    var body: some View {
        let info = env.preferences.emergencyInfo

        ScrollView {
            VStack(spacing: 20) {
                headerCard.appearTransition(delay: 0)
                stepsCard.appearTransition(delay: 0.04)

                if info.hasContent {
                    if !trimmed(info.glucagonLocation).isEmpty {
                        glucagonCard(trimmed(info.glucagonLocation)).appearTransition(delay: 0.10)
                    }
                    if !info.contacts.isEmpty {
                        contactsCard(info.contacts).appearTransition(delay: 0.14)
                    }
                    if !trimmed(info.notes).isEmpty {
                        notesCard(trimmed(info.notes)).appearTransition(delay: 0.18)
                    }
                } else {
                    setupCard.appearTransition(delay: 0.10)
                }

                footerHint.appearTransition(delay: 0.22)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Emergency card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    Haptics.play(.selection)
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            EmergencyCardEditorSheet()
        }
    }

    // MARK: Header

    /// The banner a stranger reads first. A fixed saturated red with white text
    /// so it stays high-contrast and unmistakably "medical" in both color schemes.
    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "cross.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            Text("I have diabetes")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text("If I'm confused, shaky or unconscious, this may be severe LOW blood sugar.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(hex: 0xC8323E), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Helper steps

    private var stepsCard: some View {
        SectionCard("How to help me", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 16) {
                stepRow(
                    number: 1,
                    title: "If I can swallow",
                    detail: "Give me sugar — juice, regular (non-diet) soda, or glucose tablets."
                )
                Divider().overlay(Theme.hairline)
                stepRow(
                    number: 2,
                    title: "If I can't swallow or am unconscious",
                    detail: "Do NOT give me food or drink. Use my glucagon if you can find it, and call emergency services (112 / 911)."
                )
                Divider().overlay(Theme.hairline)
                stepRow(
                    number: 3,
                    title: "Stay with me",
                    detail: "Stay until I'm fully recovered or help arrives."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepRow(number: Int, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.zoneCritical, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Personal details

    private func glucagonCard(_ location: String) -> some View {
        SectionCard("My glucagon", systemImage: "cross.vial.fill") {
            Text("My glucagon is: \(location)")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func contactsCard(_ contacts: [EmergencyContact]) -> some View {
        SectionCard("Call someone who knows me", systemImage: "phone.fill") {
            VStack(spacing: 0) {
                ForEach(contacts) { contact in
                    if let url = telURL(for: contact.phone) {
                        Link(destination: url) {
                            contactRow(contact, callable: true)
                        }
                    } else {
                        contactRow(contact, callable: false)
                    }
                    if contact.id != contacts.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
    }

    private func contactRow(_ contact: EmergencyContact, callable: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name.isEmpty ? "Contact" : contact.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(contact.phone)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            if callable {
                Image(systemName: "phone.arrow.up.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.zoneInRange, in: .circle)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(callable ? "Starts a phone call" : "")
    }

    private func notesCard(_ notes: String) -> some View {
        SectionCard("Notes for a helper", systemImage: "text.alignleft") {
            Text(notes)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Empty state

    private var setupCard: some View {
        VStack(spacing: 12) {
            Text("Add who to call and where your glucagon is kept, and this card becomes something a stranger can act on in seconds.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.play(.selection)
                showEditor = true
            } label: {
                Label("Set up your card", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var footerHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Show this screen to whoever is helping you. This is general bystander guidance, not medical advice — helpers should always call emergency services when in doubt.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A `tel:` URL from a user-typed phone number, or `nil` when no digits
    /// remain. Keeps digits and a single leading "+" so "+40 (721) 555-123"
    /// becomes "tel:+40721555123".
    private func telURL(for phone: String) -> URL? {
        let raw = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = raw.filter(\.isWholeNumber)
        guard !digits.isEmpty else { return nil }
        let number = raw.hasPrefix("+") ? "+" + digits : digits
        return URL(string: "tel:\(number)")
    }
}

// MARK: - Editor

/// Edits the emergency card: contacts (name + phone), where the glucagon is
/// kept, and free-form notes. Binds straight through to
/// `Preferences.emergencyInfo`, which persists on every change, so there is no
/// separate save step — "Done" just prunes empty contact rows and dismisses.
struct EmergencyCardEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = env.preferences
        NavigationStack {
            Form {
                Section {
                    ForEach($preferences.emergencyInfo.contacts) { $contact in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Name", text: $contact.name)
                                .font(.body.weight(.medium))
                                .textContentType(.name)
                            TextField("Phone number", text: $contact.phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { preferences.emergencyInfo.contacts.remove(atOffsets: $0) }

                    Button {
                        Haptics.play(.selection)
                        withAnimation(.snappy) {
                            preferences.emergencyInfo.contacts.append(EmergencyContact())
                        }
                    } label: {
                        Label("Add a contact", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("People to call")
                } footer: {
                    Text("Someone who knows about your diabetes — a partner, parent or friend. Their number becomes a tappable call button on the card. Swipe a contact to remove it.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField(
                        "e.g. red pouch in the kitchen drawer",
                        text: $preferences.emergencyInfo.glucagonLocation,
                        axis: .vertical
                    )
                } header: {
                    Text("Where is your glucagon?")
                } footer: {
                    Text("A helper who has never seen a glucagon kit needs to find yours fast. Name the exact place.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField(
                        "Anything else a helper should know",
                        text: $preferences.emergencyInfo.notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } header: {
                    Text("Notes for a helper")
                } footer: {
                    Text("Kept on this device, shown only on this card.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit emergency card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Drop rows the user added but never filled in, so an
                        // abandoned blank row doesn't count as card content.
                        preferences.emergencyInfo.contacts.removeAll {
                            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && $0.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Emergency card · empty") {
    let env = AppEnvironment.preview()
    return NavigationStack { EmergencyCardView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}

#Preview("Emergency card · filled") {
    // A throwaway defaults suite so the demo card never leaks into the real
    // app-group preferences on this device.
    let prefs = Preferences(defaults: UserDefaults(suiteName: "preview.emergencyCard"))
    prefs.emergencyInfo = EmergencyInfo(
        contacts: [
            EmergencyContact(name: "Ana Pop", phone: "+40 721 555 123"),
            EmergencyContact(name: "Dr. Ionescu", phone: "0721 555 987")
        ],
        glucagonLocation: "red pouch in the kitchen drawer",
        notes: "Type 1 since 2019. I wear a CGM on my left arm."
    )
    let env = AppEnvironment(modelContainer: PersistenceController.previewContainer, preferences: prefs)
    return NavigationStack { EmergencyCardView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}

#Preview("Editor") {
    let env = AppEnvironment.preview()
    return EmergencyCardEditorSheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}
