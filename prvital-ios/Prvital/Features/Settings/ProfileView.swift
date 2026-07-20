import SwiftUI

/// The person's profile: their name, an avatar, and their clinical context
/// (diabetes type, how they manage therapy, optional diagnosis year and a
/// free-text note). Local and private — it personalises the app and is the
/// identity attached when sharing with a partner or caregiver.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var profile: UserProfile

    /// A curated set of avatar glyphs.
    private let avatarOptions = [
        "person.crop.circle.fill", "figure.wave", "heart.circle.fill",
        "drop.circle.fill", "leaf.circle.fill", "star.circle.fill",
        "bolt.heart.fill", "face.smiling.inverse"
    ]

    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 90)...thisYear).reversed()
    }

    var body: some View {
        Form {
            Section {
                ProfileHeaderCard(profile: profile)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Your name", text: $profile.displayName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Name")
            } footer: {
                Text("Only used to personalise the app and label what you share. It stays on your device (and your own iCloud, if enabled).")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(avatarOptions, id: \.self) { symbol in
                        Button {
                            Haptics.play(.light)
                            profile.avatarSymbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 26))
                                .foregroundStyle(profile.avatarSymbol == symbol ? .white : Theme.accent)
                                .frame(width: 52, height: 52)
                                .background(
                                    Circle().fill(profile.avatarSymbol == symbol ? Theme.accent : Theme.accentSoft)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Avatar")
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Diabetes type", selection: $profile.diabetesType) {
                    ForEach(DiabetesType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            } header: {
                Text("Diabetes")
            } footer: {
                Text(profile.diabetesType.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Therapy", selection: $profile.therapy) {
                    ForEach(TherapyApproach.allCases) { approach in
                        Label(approach.displayName, systemImage: approach.symbol).tag(approach)
                    }
                }
            } header: {
                Text("How you manage it")
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Diagnosed", selection: Binding(
                    get: { profile.diagnosisYear ?? 0 },
                    set: { profile.diagnosisYear = $0 == 0 ? nil : $0 }
                )) {
                    Text("Not set").tag(0)
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            } header: {
                Text("Diagnosis year")
            } footer: {
                Text("Optional. Helps put your long-term trends in context.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                TextField("Care team, clinic, notes…", text: Binding(
                    get: { profile.careTeamNote ?? "" },
                    set: { profile.careTeamNote = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...5)
            } header: {
                Text("Notes")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { env.profile.save(profile) }
    }
}

/// The card at the top of the profile: avatar, name (or a prompt) and a one-line
/// clinical summary.
private struct ProfileHeaderCard: View {
    @Bindable var profile: UserProfile

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 64, height: 64)
                if let initials = profile.initials {
                    Text(initials)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: profile.avatarSymbol)
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName.isEmpty ? "Add your name" : profile.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(profile.displayName.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                Text(profile.summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { ProfileView(profile: env.profile.current()) }
        .environment(env)
        .modelContainer(env.modelContainer)
}
