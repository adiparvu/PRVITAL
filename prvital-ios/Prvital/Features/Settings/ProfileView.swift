import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// The person's profile: their name, an avatar (photo, or initials on a colour), and their
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
    @State private var photoItem: PhotosPickerItem?
    @State private var showRingPicker = false

    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 90)...thisYear).reversed()
    }

    private var birthYears: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 110)...thisYear).reversed()
    }

    var body: some View {
        Form {
            Section {
                ProfileHeaderCard(profile: profile, photoItem: $photoItem)
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
        .sheet(isPresented: $showRingPicker) {
            AvatarRingPickerSheet(selectedHex: $profile.avatarColorHex)
                .presentationDetents([.medium])
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                #if canImport(UIKit)
                profile.avatarImageData = AvatarImage.downscaledJPEG(from: data) ?? data
                #else
                profile.avatarImageData = data
                #endif
            }
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
        .glassListRow()
    }

    // MARK: - Avatar

    /// Photo picker + ring colour. Tapping the big avatar in the header also
    /// opens the photo picker; this section makes the same actions explicit and
    /// adds "remove photo" and the ring-colour sheet.
    private var avatarSection: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label {
                    Text(profile.avatarImageData == nil ? "Add a photo" : "Change photo")
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "camera.fill").foregroundStyle(Theme.accent)
                }
            }

            if profile.avatarImageData != nil {
                Button(role: .destructive) {
                    Haptics.play(.light)
                    profile.avatarImageData = nil
                    photoItem = nil
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }

            Button {
                Haptics.play(.selection)
                showRingPicker = true
            } label: {
                HStack {
                    Label {
                        Text("Ring colour").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "circle.circle.fill").foregroundStyle(ringColor)
                    }
                    Spacer()
                    Circle().fill(ringColor).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        } header: {
            Text("Avatar")
        } footer: {
            Text("Add a photo, or keep your initials on a colour. The ring colour frames your avatar and tints your initials.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    /// The chosen ring/initials colour, falling back to the app accent.
    private var ringColor: Color {
        profile.avatarColorValue.map { Color(hex: $0) } ?? Theme.accent
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
        .glassListRow()
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
        .glassListRow()
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
        .glassListRow()
    }

    private var therapyDetailsSection: some View {
        Section {
            therapyRow(.basalInsulin, value: $profile.basalInsulinName)
            therapyRow(.bolusInsulin, value: $profile.bolusInsulinName)
            therapyRow(.cgm, value: $profile.cgmModel)
            therapyRow(.meter, value: $profile.meterModel)
            if profile.therapy == .pump {
                therapyRow(.pump, value: $profile.pumpModel)
            }
        } header: {
            Text("My therapy")
        } footer: {
            Text("Tap a field to search the device and insulin list, or type your own. Labels for your records and shared reports — Prvital never recommends insulin or doses.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    /// A therapy field row: the field name, its current value (or "Optional"),
    /// and a push to the searchable 2026 catalog with free-text fallback.
    private func therapyRow(_ field: TherapyCatalog.Field, value: Binding<String?>) -> some View {
        NavigationLink {
            TherapyCatalogPicker(field: field, selection: value)
        } label: {
            HStack {
                Text(field.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(value.wrappedValue?.isEmpty == false ? value.wrappedValue! : String(localized: "Optional"))
                    .foregroundStyle(value.wrappedValue?.isEmpty == false ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
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
        .glassListRow()
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
        .glassListRow()
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
        .glassListRow()
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
        .glassListRow()
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

/// The card at the top of the profile: a tappable photo/initials avatar with a
/// camera badge and coloured ring, the name (or a prompt), the clinical one-liner
/// and — when a diagnosis year is set — how long the person has lived with
/// diabetes.
private struct ProfileHeaderCard: View {
    @Bindable var profile: UserProfile
    @Binding var photoItem: PhotosPickerItem?

    private var ring: Color {
        profile.avatarColorValue.map { Color(hex: $0) } ?? Theme.accent
    }

    var body: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        imageData: profile.avatarImageData,
                        initials: profile.initials,
                        symbol: profile.avatarSymbol,
                        tint: ring,
                        ring: ring,
                        diameter: 84
                    )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: .circle)
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")

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

/// The "Ring colour" (Inel avatar) sheet: a grid of preset tints plus a custom
/// colour well. Sets `avatarColorHex` (nil = follow the app accent).
private struct AvatarRingPickerSheet: View {
    @Binding var selectedHex: String?
    @Environment(\.dismiss) private var dismiss

    /// Fixed avatar tints ("RRGGBB"), chosen to read well on light and dark.
    private let tints: [(name: String, hex: String)] = [
        ("Ocean", "3E8DE3"), ("Violet", "8B6FE8"), ("Rose", "D6568E"),
        ("Sunset", "E1793A"), ("Amber", "C99A2E"), ("Green", "3FA968"),
        ("Slate", "8A93A6")
    ]

    private var customBinding: Binding<Color> {
        Binding(
            get: {
                guard let value = ProfileFormatting.hexColorValue(selectedHex) else { return Theme.accent }
                return Color(hex: value)
            },
            set: { newColor in selectedHex = newColor.hexString }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                    swatch(color: Theme.accent, name: String(localized: "App accent"), isSelected: selectedHex == nil) {
                        selectedHex = nil
                    }
                    ForEach(tints, id: \.hex) { tint in
                        swatch(
                            color: Color(hex: ProfileFormatting.hexColorValue(tint.hex) ?? 0),
                            name: tint.name,
                            isSelected: selectedHex?.uppercased() == tint.hex.uppercased()
                        ) {
                            selectedHex = tint.hex
                        }
                    }
                }
                .padding()

                ColorPicker(selection: customBinding, supportsOpacity: false) {
                    Label("Custom colour", systemImage: "eyedropper.halffull")
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding()
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .padding(.horizontal)
            }
            .background(Theme.background)
            .navigationTitle("Ring colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func swatch(color: Color, name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            ZStack {
                Circle().fill(color).frame(width: 52, height: 52)
                if isSelected {
                    Circle().strokeBorder(Theme.textPrimary.opacity(0.9), lineWidth: 3).frame(width: 62, height: 62)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
