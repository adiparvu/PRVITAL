import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Appearance, rebuilt as a quiet hub: the theme lives on its own page, the
/// accent is a grid of colour swatches (same language as the avatar-ring
/// picker), and each display toggle explains itself in a one-line caption. The
/// glucose zone colours (green / yellow / orange / red) are medical semantics
/// and never change with any of these.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var selected: AccentTheme {
        AccentTheme(rawValue: env.preferences.accentThemeRaw) ?? .default
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        return Form {
            // Theme (light / dark / system) on its own page.
            Section {
                NavigationLink {
                    ThemeModeSettingsView()
                } label: {
                    LabeledContent {
                        Text(prefs.themeMode.displayName)
                    } label: {
                        Label {
                            Text("Theme").foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: prefs.themeMode.symbol)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .glassListRow()

            // Accent: a grid of swatch circles, like the avatar-ring picker.
            Section {
                AccentSwatchGrid(selected: selected) { theme in
                    guard theme != selected else { return }
                    Haptics.play(.selection)
                    env.preferences.accentThemeRaw = theme.rawValue
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .listRowBackground(Color.clear)
            } header: {
                Text("Accent colour")
            } footer: {
                Text("The accent tints buttons, icons and highlights across the app. Glucose zone colours never change, so readings always mean the same thing. Widgets and the Watch app pick up the new colour the next time they refresh.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Display: text size + background links.
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
            } header: {
                Text("Display")
            } footer: {
                Text("Text size and the background apply to Prvital only.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            // Little extras, each with a one-line caption instead of one long
            // footer paragraph.
            Section {
                captionedToggle("Haptic feedback",
                                caption: "A gentle tap on key actions.",
                                isOn: $prefs.hapticsEnabled)
                captionedToggle("Daily companion",
                                caption: "A friendly note at the top of the dashboard.",
                                isOn: $prefs.showDailyCompanion)
                captionedToggle("Contextual lessons",
                                caption: "Suggests a relevant article after a low or high.",
                                isOn: $prefs.showContextualLessons)
                captionedToggle("Minimalist icons",
                                caption: "Plain monochrome glyphs instead of coloured circles.",
                                isOn: $prefs.minimalistIcons)
                captionedToggle("Yesterday's curve",
                                caption: "Yesterday drawn as a faint line under today's chart.",
                                isOn: $prefs.showYesterdayShadow)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A toggle whose explanation lives right under its title.
    private func captionedToggle(
        _ title: LocalizedStringKey, caption: LocalizedStringKey, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { value in
                if value { Haptics.play(.selection) }
                isOn.wrappedValue = value
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(caption).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.accent)
    }

    private var backgroundSubtitle: String {
        switch env.preferences.backgroundKind {
        case .standard: String(localized: "Standard")
        case .gradient: env.preferences.backgroundGradient.displayName
        case .photo: String(localized: "Your photo")
        }
    }
}

/// The theme's own page: system / light / dark as tappable rows.
struct ThemeModeSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        return Form {
            Section {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        guard prefs.themeMode != mode else { return }
                        Haptics.play(.selection)
                        prefs.themeMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26)
                            Text(mode.displayName)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if prefs.themeMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(prefs.themeMode == mode ? [.isSelected] : [])
                }
            } footer: {
                Text("Choose light or dark, or follow your device's setting.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The accent swatches: circles in a four-column grid, a bold ring plus a
/// checkmark on the current choice — the same visual language as the
/// avatar-ring picker in Profile.
private struct AccentSwatchGrid: View {
    let selected: AccentTheme
    let choose: (AccentTheme) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
            ForEach(AccentTheme.allCases) { theme in
                Button {
                    Haptics.play(.light)
                    choose(theme)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(theme.swatch).frame(width: 52, height: 52)
                            if theme == selected {
                                Circle()
                                    .strokeBorder(Theme.textPrimary.opacity(0.9), lineWidth: 3)
                                    .frame(width: 62, height: 62)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 64)
                        Text(theme.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme == selected ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(theme.displayName))
                .accessibilityAddTraits(theme == selected ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.2), value: selected)
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

/// The Background page: a live sample card, the background type as tile rows
/// with round selection marks, and — for a photo — the change-photo row with a
/// thumbnail, a dimming-for-legibility slider, and a destructive remove row.
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
            }

            Section {
                backgroundKindRow(.standard, title: "Standard",
                                  subtitle: "The calm default surface.",
                                  symbol: "square.fill", prefs: prefs)
                backgroundKindRow(.gradient, title: "Gradient",
                                  subtitle: "A soft, static wash of colour.",
                                  symbol: "square.stack.3d.down.right.fill", prefs: prefs)
                backgroundKindRow(.photo, title: "Your photo",
                                  subtitle: "Choose an image from your library.",
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
                    // Copied into a `let` first: the PhotosPicker label closure
                    // is @Sendable and must not capture the mutable `prefs`.
                    let photoData = prefs.backgroundPhotoData
                    let thumb = BackgroundPhotoStore.shared.image(matching: photoData)
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 12) {
                            tile("photo.badge.plus")
                            Text(photoData == nil ? "Choose photo" : "Change photo")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let thumb {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    if prefs.backgroundPhotoData != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dimming for legibility")
                                .foregroundStyle(Theme.textPrimary)
                            Slider(value: $prefs.backgroundPhotoDimming, in: 0...0.7) { editing in
                                if !editing { Haptics.play(.selection) }
                            }
                            .tint(Theme.accent)
                        }
                        .padding(.vertical, 2)

                        Button(role: .destructive) {
                            Haptics.play(.selection)
                            prefs.backgroundPhotoData = nil
                        } label: {
                            HStack(spacing: 12) {
                                tile("trash")
                                Text("Remove photo")
                            }
                        }
                    }
                } header: {
                    Text("Your photo")
                } footer: {
                    Text("The photo stays on your phone; text picks its own colour from its brightness.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.large)
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

    /// A small neutral squircle behind a row's glyph, like the reference rows.
    /// Nonisolated (pure view construction) so the @Sendable PhotosPicker
    /// label closure can call it too.
    private nonisolated func tile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 34, height: 34)
            .background(Theme.textPrimary.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func sampleCard(prefs: Preferences) -> some View {
        ZStack {
            AppBackgroundView(
                kind: prefs.backgroundKind,
                gradient: prefs.backgroundGradient,
                photoData: prefs.backgroundPhotoData,
                photoDimming: prefs.backgroundPhotoDimming
            )
            Text("Sample card")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                .padding(24)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.vertical, 4)
        .animation(.smooth, value: prefs.backgroundKindRaw)
        .animation(.smooth, value: prefs.backgroundGradientRaw)
        .animation(.smooth, value: prefs.backgroundPhotoDimming)
    }

    private func backgroundKindRow(
        _ kind: AppBackgroundKind, title: LocalizedStringKey, subtitle: LocalizedStringKey,
        symbol: String, prefs: Preferences
    ) -> some View {
        Button {
            guard prefs.backgroundKind != kind else { return }
            Haptics.play(.selection)
            prefs.backgroundKind = kind
        } label: {
            HStack(spacing: 12) {
                tile(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: prefs.backgroundKind == kind ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(prefs.backgroundKind == kind ? Theme.accent : Theme.textTertiary)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(prefs.backgroundKind == kind ? [.isSelected] : [])
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

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AppearanceSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
