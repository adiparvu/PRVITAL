import SwiftUI

/// Appearance. Picks the accent theme that tints buttons, glyphs and highlights
/// across the app, with a live preview card. The glucose zone colours
/// (green / yellow / orange / red) are medical semantics and never change with
/// the theme.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var selected: AccentTheme {
        AccentTheme(rawValue: env.preferences.accentThemeRaw) ?? .default
    }

    var body: some View {
        Form {
            Section {
                AccentPreviewCard(theme: selected)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Preview")
            }

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
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Private helpers

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
