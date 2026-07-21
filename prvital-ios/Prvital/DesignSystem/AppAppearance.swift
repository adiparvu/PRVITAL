import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Appearance choices the user makes in Settings → Appearance, beyond the accent
/// colour: the light/dark mode, the in-app text size, and the app background.
///
/// Each type resolves from the shared App Group defaults through a `current`
/// accessor (mirroring `AccentTheme.current`) so any target that links this file
/// reads the same choice. The keys are duplicated as string literals rather than
/// referencing `Preferences`, which doesn't exist in the widget/watch targets.

// MARK: - Theme mode (light / dark / system)

/// How the app resolves its colour scheme.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static let preferenceKey = "pref.themeMode"

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    /// The scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Text size

/// The in-app Dynamic Type override. Applied only when the user turns off
/// "Use system size"; otherwise Prvital follows the system Dynamic Type setting.
enum AppTextSize: String, CaseIterable, Identifiable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge

    var id: String { rawValue }

    static let preferenceKey = "pref.textSize"

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        }
    }

    /// Short label for the size slider ticks.
    var shortLabel: String {
        switch self {
        case .xSmall: "XS"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .xLarge: "XL"
        case .xxLarge: "XXL"
        }
    }
}

// MARK: - Background

/// What fills the app's background behind the cards.
enum AppBackgroundKind: String, CaseIterable, Identifiable {
    /// The standard calm surface (`Theme.background`) — the default look.
    case standard
    /// One of the built-in gradient presets.
    case gradient
    /// A photo the user chose from their library.
    case photo

    var id: String { rawValue }

    static let preferenceKey = "pref.backgroundKind"
    static let photoKey = "pref.backgroundPhoto"
}

/// The built-in background gradients. Each is defined with light and dark stops
/// so it reads well in both modes while the opaque cards stay legible on top.
enum BackgroundGradient: String, CaseIterable, Identifiable {
    case aurora
    case ocean
    case dawn
    case graphite

    var id: String { rawValue }

    static let preferenceKey = "pref.backgroundGradient"

    var displayName: String {
        switch self {
        case .aurora: String(localized: "Aurora")
        case .ocean: String(localized: "Ocean")
        case .dawn: String(localized: "Dawn")
        case .graphite: String(localized: "Graphite")
        }
    }

    /// Top and bottom stops for (light, dark).
    private var stops: (light: (UInt, UInt), dark: (UInt, UInt)) {
        switch self {
        case .aurora:   ((0xCDEFE8, 0xDCE4FF), (0x07231F, 0x0B1320))
        case .ocean:    ((0xD5EAFF, 0xEFF5FC), (0x0A1B2E, 0x0A0E15))
        case .dawn:     ((0xF7E3ED, 0xFCEADB), (0x2A1622, 0x231820))
        case .graphite: ((0xE7E9EE, 0xF2F3F7), (0x11141A, 0x05070A))
        }
    }

    /// The full-screen gradient, adapting to light/dark.
    var gradient: LinearGradient {
        let s = stops
        return LinearGradient(
            colors: [
                Color.adaptive(light: s.light.0, dark: s.dark.0),
                Color.adaptive(light: s.light.1, dark: s.dark.1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// A compact swatch gradient for the picker tiles (uses the light stops so the
    /// tiles read as previews of the mood, regardless of the current scheme).
    var swatchGradient: LinearGradient {
        let s = stops
        return LinearGradient(
            colors: [Color(hex: s.light.0), Color(hex: s.light.1)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Current values from shared defaults

extension AppBackgroundKind {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupIdentifier)
    }

    static var current: AppBackgroundKind {
        defaults?.string(forKey: preferenceKey).flatMap(AppBackgroundKind.init(rawValue:)) ?? .standard
    }

    static var currentGradient: BackgroundGradient {
        defaults?.string(forKey: BackgroundGradient.preferenceKey)
            .flatMap(BackgroundGradient.init(rawValue:)) ?? .aurora
    }

    static var currentPhotoData: Data? {
        defaults?.data(forKey: photoKey)
    }
}

// MARK: - The background view + screen modifier

/// Renders the currently-chosen app background. Falls back to the standard
/// surface, so it is always safe to place behind any screen.
struct AppBackgroundView: View {
    var kind: AppBackgroundKind = .current
    var gradient: BackgroundGradient = AppBackgroundKind.currentGradient
    var photoData: Data? = AppBackgroundKind.currentPhotoData

    var body: some View {
        switch kind {
        case .standard:
            Theme.background
        case .gradient:
            gradient.gradient
        case .photo:
            photoView
        }
    }

    @ViewBuilder
    private var photoView: some View {
        #if canImport(UIKit)
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // A soft scrim keeps cards and text legible over any photo.
                .overlay(Theme.background.opacity(0.28))
        } else {
            Theme.background
        }
        #else
        Theme.background
        #endif
    }
}

extension View {
    /// Paints the user's chosen app background (gradient / photo / standard)
    /// behind this screen, ignoring safe areas. Reads the live preference values,
    /// so a change on the Appearance screen is reflected immediately.
    func prvitalScreenBackground() -> some View {
        background {
            AppBackgroundView()
                .ignoresSafeArea()
        }
    }
}
