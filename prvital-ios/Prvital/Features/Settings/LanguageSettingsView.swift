import SwiftUI

/// Language picker. Prvital normally follows the device language, but this page
/// lets you force a specific one for the app alone. The choice is written to the
/// app's `AppleLanguages` default, which the system reads at launch — so it takes
/// full effect the next time the app is opened.
struct LanguageSettingsView: View {
    @State private var selected: String? = LanguageSettingsView.currentCode()
    @State private var showReopenNote = false

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
                Text("Choose the language Prvital uses. Reopen the app for the change to take full effect. This affects Prvital only, not the rest of your device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .prvitalTabBackground()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reopen Prvital", isPresented: $showReopenNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close Prvital from the app switcher and open it again for the new language to appear everywhere.")
        }
    }

    private func languageRow(code: String?, title: Text) -> some View {
        Button {
            apply(code)
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

    private func apply(_ code: String?) {
        guard code != selected else { return }
        Haptics.play(.success)
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            // Fall back to the device language.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        selected = code
        showReopenNote = true
    }

    /// The current forced language code (2-letter), or nil when following the
    /// device. `AppleLanguages` entries can be region-qualified (e.g. "ro-RO"),
    /// so compare on the language prefix.
    private static func currentCode() -> String? {
        guard let stored = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
        else { return nil }
        let prefix = String(stored.prefix(2))
        return languages.contains { $0.code == prefix } ? prefix : nil
    }

    /// The current choice's native name (or "System default") — used as the
    /// Settings row subtitle.
    static var currentDisplayName: String {
        guard let code = currentCode() else { return String(localized: "System default") }
        return languages.first { $0.code == code }?.native ?? code
    }
}
