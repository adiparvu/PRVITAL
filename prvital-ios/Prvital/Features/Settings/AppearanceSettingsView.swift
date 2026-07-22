import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Appearance. The accent theme that tints buttons, glyphs and highlights, plus
/// the light/dark mode, text size, haptics and the app background. The glucose
/// zone colours (green / yellow / orange / red) are medical semantics and never
/// change with any of these.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var selected: AccentTheme {
        AccentTheme(rawValue: env.preferences.accentThemeRaw) ?? .default
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        return Form {
            Section {
                AccentPreviewCard(theme: selected)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Preview")
            }

            // Light / dark / system.
            Section {
                Picker("Theme", selection: $prefs.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.themeModeRaw) { _, _ in Haptics.play(.selection) }
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose light or dark, or follow your device's setting.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                ForEach(AccentTheme.allCases) { theme in
                    Button {
                        guard theme != selected else { return }
                        Haptics.play(.selection)
                        env.preferences.accentThemeRaw = theme.rawValue
                    } label: {
                        AccentThemeRow(theme: theme, isSelected: theme == selected)
                    }
                }
            } header: {
                Text("Accent colour")
            } footer: {
                Text("The accent tints buttons, icons and highlights across the app. Glucose zone colours never change, so readings always mean the same thing. Widgets and the Watch app pick up the new colour the next time they refresh.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            // Display: text size, background, haptics.
            Section {
                NavigationLink {
                    TextSizeSettingsView()
                } label: {
                    LabeledContent("Text size") {
                        Text(prefs.useSystemTextSize ? String(localized: "System") : prefs.textSize.shortLabel)
                    }
                }

                NavigationLink {
                    BackgroundSettingsView()
                } label: {
                    LabeledContent("Background") {
                        Text(backgroundSubtitle)
                    }
                }

                Toggle(isOn: $prefs.hapticsEnabled) {
                    Text("Haptic feedback")
                }
                .onChange(of: prefs.hapticsEnabled) { _, isOn in
                    // Only confirm turning it on — a tap that disables haptics
                    // shouldn't itself buzz.
                    if isOn { Haptics.play(.selection) }
                }

                Toggle(isOn: $prefs.showDailyCompanion) {
                    Text("Daily companion")
                }
                .onChange(of: prefs.showDailyCompanion) { _, isOn in
                    if isOn { Haptics.play(.selection) }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Text size and background apply to Prvital only. Haptics add a gentle tap to key actions. The daily companion is a friendly, encouraging note at the top of your dashboard.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var backgroundSubtitle: String {
        switch env.preferences.backgroundKind {
        case .standard: String(localized: "Standard")
        case .gradient: env.preferences.backgroundGradient.displayName
        case .photo: String(localized: "Your photo")
        }
    }
}

// MARK: - Text size

/// A dedicated text-size screen: a live preview card, a "use system size" toggle
/// and — when the user opts out — a size picker that overrides Dynamic Type for
/// Prvital only.
struct TextSizeSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        return Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your day, in one place")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Glucose, insulin, meals and notes — clear at the size that suits you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .dynamicTypeSize(prefs.useSystemTextSize ? .large : prefs.textSize.dynamicTypeSize)
                .animation(.snappy, value: prefs.textSizeRaw)
                .glassListRow()
            } header: {
                Text("Preview")
            }

            Section {
                Toggle(isOn: $prefs.useSystemTextSize) {
                    Label {
                        Text("Use system size")
                    } icon: {
                        Image(systemName: "textformat.size")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .onChange(of: prefs.useSystemTextSize) { _, _ in Haptics.play(.selection) }

                if !prefs.useSystemTextSize {
                    Picker("Size", selection: $prefs.textSize) {
                        ForEach(AppTextSize.allCases) { size in
                            Text(size.shortLabel).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: prefs.textSizeRaw) { _, _ in Haptics.play(.selection) }
                }
            } header: {
                Text("Size")
            } footer: {
                Text("The chosen size applies to text in Prvital. Other apps keep following the system setting.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Text size")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background

/// The app background chooser: a standard surface, one of four gradient presets,
/// or a photo from the user's library — with a live sample card on top.
struct BackgroundSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var prefs = env.preferences

        return Form {
            Section {
                sampleCard(prefs: prefs)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Preview")
            }

            Section {
                backgroundKindRow(.standard, title: String(localized: "Standard"),
                                  subtitle: String(localized: "The calm default surface."),
                                  symbol: "square.fill", prefs: prefs)
                backgroundKindRow(.gradient, title: String(localized: "Gradient"),
                                  subtitle: String(localized: "A soft, static wash of colour."),
                                  symbol: "square.stack.3d.down.right.fill", prefs: prefs)
                backgroundKindRow(.photo, title: String(localized: "Your photo"),
                                  subtitle: String(localized: "Choose an image from your library."),
                                  symbol: "photo.fill", prefs: prefs)
            } header: {
                Text("Background type")
            }
            .glassListRow()

            if prefs.backgroundKind == .gradient {
                Section {
                    gradientGrid(prefs: prefs)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if prefs.backgroundKind == .photo {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(prefs.backgroundPhotoData == nil ? "Choose photo" : "Change photo",
                              systemImage: "photo.on.rectangle")
                            .foregroundStyle(Theme.accent)
                    }
                    if prefs.backgroundPhotoData != nil {
                        Button("Remove photo", role: .destructive) {
                            Haptics.play(.selection)
                            prefs.backgroundPhotoData = nil
                        }
                    }
                } footer: {
                    Text("Your photo stays on this device and is used only as the app background.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    env.preferences.backgroundPhotoData = data
                    env.preferences.backgroundKind = .photo
                }
            }
        }
    }

    private func sampleCard(prefs: Preferences) -> some View {
        ZStack {
            AppBackgroundView(
                kind: prefs.backgroundKind,
                gradient: prefs.backgroundGradient,
                photoData: prefs.backgroundPhotoData
            )
            Text("Sample card")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .padding(24)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.vertical, 4)
        .animation(.smooth, value: prefs.backgroundKindRaw)
        .animation(.smooth, value: prefs.backgroundGradientRaw)
    }

    private func backgroundKindRow(
        _ kind: AppBackgroundKind, title: String, subtitle: String, symbol: String, prefs: Preferences
    ) -> some View {
        Button {
            guard prefs.backgroundKind != kind else { return }
            Haptics.play(.selection)
            prefs.backgroundKind = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if prefs.backgroundKind == kind {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func gradientGrid(prefs: Preferences) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(BackgroundGradient.allCases) { preset in
                Button {
                    Haptics.play(.selection)
                    prefs.backgroundGradient = preset
                    prefs.backgroundKind = .gradient
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(preset.swatchGradient)
                            .frame(height: 74)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        prefs.backgroundGradient == preset ? Theme.accent : Theme.hairline,
                                        lineWidth: prefs.backgroundGradient == preset ? 2.5 : 1
                                    )
                            }
                        Text(preset.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(prefs.backgroundGradient == preset ? Theme.accent : Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Accent preview & rows

/// A mock dashboard card — a Time-in-Range ring and a log pill — tinted with the
/// chosen accent, so a theme change is visible before leaving the screen. Purely
/// illustrative, so it's hidden from VoiceOver (the picker rows below carry the
/// real selection).
private struct AccentPreviewCard: View {
    let theme: AccentTheme

    var body: some View {
        SectionCard("Today", systemImage: "heart.text.square") {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(theme.accent.opacity(0.18), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("72%")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Time in range")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A sample card in your accent")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text("Log")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.accent, in: .capsule)
            }
        }
        .animation(.smooth, value: theme)
        .accessibilityHidden(true)
    }
}

/// One selectable theme: a swatch circle, the theme's name and a checkmark on
/// the current choice.
private struct AccentThemeRow: View {
    let theme: AccentTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.swatch)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .accessibilityHidden(true)

            Text(theme.displayName)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AppearanceSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
