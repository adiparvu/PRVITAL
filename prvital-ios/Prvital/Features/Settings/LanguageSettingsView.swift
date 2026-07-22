import SwiftUI

/// Language picker. Prvital normally follows the device language, but this page
/// lets you force one for the app alone — and it applies **instantly**, with no
/// restart (see `LanguageManager`).
struct LanguageSettingsView: View {
    @State private var selected: String? = LanguageManager.shared.code

    /// The app's supported languages, shown in their own script.
    private static let languages: [(code: String, native: String)] = [
        ("ro", "Română"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("pt", "Português"),
        ("ru", "Русский"),
    ]

    var body: some View {
        Form {
            Section {
                languageRow(code: nil, title: Text("System default"))
                ForEach(Self.languages, id: \.code) { lang in
                    languageRow(code: lang.code, title: Text(lang.native))
                }
            } footer: {
                Text("The app switches language immediately. This affects Prvital only, not the rest of your device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalTabBackground()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func languageRow(code: String?, title: Text) -> some View {
        Button {
            guard code != selected else { return }
            Haptics.play(.success)
            LanguageManager.shared.set(code)
            selected = code
        } label: {
            HStack {
                title.foregroundStyle(Theme.textPrimary)
                Spacer()
                if selected == code {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The current choice's native name (or "System default") — used as the
    /// Settings row subtitle.
    @MainActor static var currentDisplayName: String {
        guard let code = LanguageManager.shared.code else { return String(localized: "System default") }
        return languages.first { $0.code == code }?.native ?? code
    }
}
