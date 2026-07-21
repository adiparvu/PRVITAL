import SwiftUI

/// The person's profile: their name, an avatar (symbol + colour), and their
/// clinical context — diabetes type, therapy, the insulins and devices they use,
/// their care team, and optional personal details (birth year, weight, height).
/// Local and private — it personalises the app and is the identity attached when
/// sharing with a partner or caregiver. Nothing here is ever used to calculate
/// or suggest insulin doses.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var profile: UserProfile

    @State private var weightText = ""
    @State private var heightText = ""
    @State private var showGoalsEditor = false

    /// A curated set of avatar glyphs.
    private let avatarOptions = [
        "person.crop.circle.fill", "figure.wave", "heart.circle.fill",
        "drop.circle.fill", "leaf.circle.fill", "star.circle.fill",
        "bolt.heart.fill", "face.smiling.inverse"
    ]

    /// Fixed avatar tints ("RRGGBB"), chosen to read well on both light and dark
    /// surfaces. A `nil` `avatarColorHex` means "follow the app accent".
    private let avatarTints: [(name: String, hex: String)] = [
        ("Ocean", "3E8DE3"), ("Violet", "8B6FE8"), ("Rose", "D6568E"),
        ("Sunset", "E1793A"), ("Amber", "C99A2E"), ("Green", "3FA968"),
        ("Slate", "8A93A6")
    ]

    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 90)...thisYear).reversed()
    }

    private var birthYears: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 110)...thisYear).reversed()
    }

    /// The chosen avatar tint, falling back to the app accent.
    private var avatarTint: Color {
        profile.avatarColorValue.map { Color(hex: $0) } ?? Theme.accent
    }

    /// A soft wash of the avatar tint for chip and circle backgrounds.
    private var avatarTintSoft: Color {
        profile.avatarColorValue.map { Color(hex: $0, alpha: 0.16) } ?? Theme.accentSoft
    }

    var body: some View {
        Form {
            Section {
                ProfileHeaderCard(profile: profile)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            nameSection
            avatarSection
            aboutYouSection
            diabetesSection
            therapySection
            therapyDetailsSection
            diagnosisSection
            careTeamSection
            quickLinksSection
            notesSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGoalsEditor) {
            GoalsEditorSheet()
        }
        .onAppear {
            weightText = ProfileFormatting.measurementText(profile.weightKg)
            heightText = ProfileFormatting.measurementText(profile.heightCm)
        }
        .onChange(of: weightText) { _, newValue in
            profile.weightKg = ProfileFormatting.measurement(from: newValue)
        }
        .onChange(of: heightText) { _, newValue in
            profile.heightCm = ProfileFormatting.measurement(from: newValue)
        }
        .onDisappear { env.profile.save(profile) }
    }

    // MARK: - Name

    private var nameSection: some View {
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
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    Button {
                        Haptics.play(.light)
                        profile.avatarSymbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 26))
                            .foregroundStyle(profile.avatarSymbol == symbol ? .white : avatarTint)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle().fill(profile.avatarSymbol == symbol ? avatarTint : avatarTintSoft)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    colorSwatch(
                        color: Theme.accent,
                        name: "App accent",
                        isSelected: profile.avatarColorHex == nil
                    ) {
                        profile.avatarColorHex = nil
                    }
                    ForEach(avatarTints, id: \.hex) { tint in
                        colorSwatch(
                            color: Color(hex: ProfileFormatting.hexColorValue(tint.hex) ?? 0),
                            name: tint.name,
                            isSelected: profile.avatarColorHex == tint.hex
                        ) {
                            profile.avatarColorHex = tint.hex
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Avatar")
        } footer: {
            Text("Pick a symbol and a colour. Once you've added your name, your initials take the symbol's place.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowBackground(Theme.surface)
    }

    private func colorSwatch(
        color: Color, name: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - About you

    private var aboutYouSection: some View {
        Section {
            Picker("Birth year", selection: Binding(
                get: { profile.birthYear ?? 0 },
                set: { profile.birthYear = $0 == 0 ? nil : $0 }
            )) {
                Text("Not set").tag(0)
                ForEach(birthYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }

            LabeledContent("Weight") {
                HStack(spacing: 6) {
                    TextField("Optional", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text("kg")
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            LabeledContent("Height") {
                HStack(spacing: 6) {
                    TextField("Optional", text: $heightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text("cm")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("About you")
        } footer: {
            Text("All optional — kept only for your own record and the clinician report. Prvital never uses them to calculate or suggest doses.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Diabetes & therapy

    private var diabetesSection: some View {
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
    }

    private var therapySection: some View {
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
    }

    private var therapyDetailsSection: some View {
        Section {
            LabeledContent("Basal insulin") {
                TextField("Optional", text: nonOptional($profile.basalInsulinName))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("Bolus insulin") {
                TextField("Optional", text: nonOptional($profile.bolusInsulinName))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("CGM / sensor") {
                TextField("Optional", text: nonOptional($profile.cgmModel))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("Meter") {
                TextField("Optional", text: nonOptional($profile.meterModel))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            if profile.therapy == .pump {
                LabeledContent("Pump") {
                    TextField("Optional", text: nonOptional($profile.pumpModel))
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("My therapy")
        } footer: {
            Text("Free-text labels for your own records and shared reports — handy at appointments. Prvital never recommends insulin or doses.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowBackground(Theme.surface)
    }

    private var diagnosisSection: some View {
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
    }

    // MARK: - Care team

    private var careTeamSection: some View {
        Section {
            LabeledContent("Doctor / clinic") {
                TextField("Optional", text: nonOptional($profile.doctorName))
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Phone") {
                TextField("Optional", text: nonOptional($profile.doctorPhone))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            if let phone = profile.doctorPhone, let url = ProfileFormatting.telURL(from: phone) {
                Link(destination: url) {
                    Label(callButtonTitle, systemImage: "phone.fill")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityHint("Starts a phone call")
            }

            if profile.nextAppointment != nil {
                DatePicker("Next appointment", selection: Binding(
                    get: { profile.nextAppointment ?? Date() },
                    set: { profile.nextAppointment = $0 }
                ), displayedComponents: .date)

                if let countdown = appointmentCountdown {
                    Label(countdown, systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }

                Button("Remove appointment date", role: .destructive) {
                    Haptics.play(.light)
                    withAnimation(.snappy) { profile.nextAppointment = nil }
                }
            } else {
                Button {
                    Haptics.play(.selection)
                    withAnimation(.snappy) {
                        profile.nextAppointment = Calendar.current.date(
                            byAdding: .day, value: 7, to: Date()
                        ) ?? Date()
                    }
                } label: {
                    Label("Add next appointment", systemImage: "calendar.badge.plus")
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Care team")
        } footer: {
            Text("The phone number becomes a call button. An appointment within the next 30 days shows a countdown.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowBackground(Theme.surface)
    }

    private var callButtonTitle: String {
        if let name = profile.doctorName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Call \(name)"
        }
        return "Call care team"
    }

    private var appointmentCountdown: String? {
        guard let date = profile.nextAppointment else { return nil }
        return ProfileFormatting.appointmentCountdown(daysAway: ProfileFormatting.daysUntil(date))
    }

    // MARK: - Quick links

    private var quickLinksSection: some View {
        Section {
            NavigationLink {
                EmergencyCardView()
            } label: {
                Label {
                    Text("Emergency card")
                } icon: {
                    Image(systemName: "cross.circle.fill")
                        .foregroundStyle(Theme.zoneCritical)
                }
            }

            Button {
                Haptics.play(.selection)
                showGoalsEditor = true
            } label: {
                Label {
                    Text("Glucose goals")
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "target")
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Quick links")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section {
            TextField("Anything you want on hand…", text: Binding(
                get: { profile.careTeamNote ?? "" },
                set: { profile.careTeamNote = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...5)
        } header: {
            Text("Notes")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Helpers

    /// Bridges an optional-string model field to a text field, storing nil
    /// instead of "" so empty fields stay absent (CloudKit-friendly).
    private func nonOptional(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

/// The card at the top of the profile: a large tinted avatar, the name (or a
/// prompt), the clinical one-liner and — when a diagnosis year is set — how long
/// the person has lived with diabetes.
private struct ProfileHeaderCard: View {
    @Bindable var profile: UserProfile

    private var tint: Color {
        profile.avatarColorValue.map { Color(hex: $0) } ?? Theme.accent
    }

    private var tintSoft: Color {
        profile.avatarColorValue.map { Color(hex: $0, alpha: 0.16) } ?? Theme.accentSoft
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(tintSoft).frame(width: 84, height: 84)
                if let initials = profile.initials {
                    Text(initials)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: profile.avatarSymbol)
                        .font(.system(size: 38))
                        .foregroundStyle(tint)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName.isEmpty ? "Add your name" : profile.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(profile.displayName.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                Text(profile.summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if let years = profile.yearsWithDiabetes {
                    Text(ProfileFormatting.durationLine(yearsWithDiabetes: years))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
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

#Preview("Filled") {
    let env = AppEnvironment.preview()
    let profile = env.profile.current()
    profile.displayName = "Ana Pop"
    profile.avatarColorHex = "8B6FE8"
    profile.diagnosisYear = 2019
    profile.birthYear = 1992
    profile.weightKg = 68
    profile.heightCm = 172
    profile.basalInsulinName = "Glargine (Lantus)"
    profile.bolusInsulinName = "Aspart (NovoRapid)"
    profile.cgmModel = "Dexcom G7"
    profile.doctorName = "Dr. Ionescu"
    profile.doctorPhone = "+40 721 555 987"
    profile.nextAppointment = Calendar.current.date(byAdding: .day, value: 12, to: Date())
    return NavigationStack { ProfileView(profile: profile) }
        .environment(env)
        .modelContainer(env.modelContainer)
}
