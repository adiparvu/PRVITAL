import SwiftUI
import ObjectiveC

/// Runtime language override. Prvital normally follows the device, but the user
/// can force one language (Settings → App → Language) and see it apply
/// **instantly**, no restart. Two mechanisms together cover the whole app:
///   • a `Bundle.main` re-class so Foundation's `String(localized:)` /
///     `NSLocalizedString` read the chosen `.lproj`, and
///   • the SwiftUI `\.locale` environment plus a root-view identity keyed on the
///     language, so every `Text` re-resolves the moment the choice changes.
@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    /// The app's supported UI languages (matches CFBundleLocalizations).
    static let supported: [String] = ["ro", "en", "de", "es", "fr", "it", "nl", "pl", "pt", "ru"]

    /// The forced language code (2-letter), or nil to follow the device.
    private(set) var code: String?

    private init() {
        let stored = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?
            .first.map { String($0.prefix(2)) }
        code = stored.flatMap { Self.supported.contains($0) ? $0 : nil }
        Bundle.setPrvitalLanguage(code)
    }

    /// The locale SwiftUI resolves `Text` against (and formats dates/numbers with).
    var locale: Locale { code.map { Locale(identifier: $0) } ?? Locale.autoupdatingCurrent }

    /// Changes whenever the language does — used to key the root view so the whole
    /// tree rebuilds in the new language at once.
    var renderID: String { code ?? "system" }

    func set(_ newCode: String?) {
        guard newCode != code else { return }
        code = newCode
        if let newCode {
            UserDefaults.standard.set([newCode], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        Bundle.setPrvitalLanguage(newCode)
    }
}

// MARK: - Bundle language override

extension Bundle {
    private static let installPrvitalSwizzle: Void = {
        object_setClass(Bundle.main, PrvitalLanguageBundle.self)
    }()

    /// Point Foundation localization at the chosen language's `.lproj` (or clear
    /// the override to fall back to the device language).
    static func setPrvitalLanguage(_ code: String?) {
        _ = installPrvitalSwizzle
        if let code, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            PrvitalLanguageBundle.override = Bundle(path: path)
        } else {
            PrvitalLanguageBundle.override = nil
        }
    }
}

/// `Bundle.main` is re-classed to this so string lookups read from the forced
/// language's bundle when one is set, and fall back to normal behaviour otherwise.
private final class PrvitalLanguageBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var override: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = PrvitalLanguageBundle.override {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
