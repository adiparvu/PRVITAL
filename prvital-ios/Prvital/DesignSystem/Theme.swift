import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Design tokens for Prvital.
///
/// A calm, Health-app-inspired palette that adapts to light and dark mode. The
/// glucose zone colours are the semantic heart of the system — green / yellow /
/// orange / red — and every value in the app is tinted through them.
enum Theme {
    // Surfaces
    static let background = Color.adaptive(light: 0xF2F3F7, dark: 0x0B0E14)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x161A22)
    static let surfaceRaised = Color.adaptive(light: 0xFFFFFF, dark: 0x1E232D)

    // Text
    static let textPrimary = Color.adaptive(light: 0x11131A, dark: 0xF5F7FA)
    static let textSecondary = Color.adaptive(light: 0x6B7280, dark: 0x9BA1AC)
    static let textTertiary = Color.adaptive(light: 0x9AA0AA, dark: 0x6B7280)

    // Brand accent — a medical teal by default, user-selectable in Settings →
    // Appearance. Computed (not stored) so every render resolves the theme the
    // user chose from the shared App Group defaults; CFPrefs caches the lookup,
    // so the read is cheap.
    static var accent: Color { AccentTheme.current.accent }
    static var accentSoft: Color { AccentTheme.current.accentSoft }

    // Glucose zone colours (green → yellow → orange → red).
    static let zoneInRange = Color.adaptive(light: 0x2FB86B, dark: 0x34D07A)
    static let zoneHigh = Color.adaptive(light: 0xE0A100, dark: 0xF5C242)   // yellow
    static let zoneWarning = Color.adaptive(light: 0xE8730C, dark: 0xF7913D) // orange
    static let zoneCritical = Color.adaptive(light: 0xD64550, dark: 0xF2626B) // red

    static let hairline = Color.adaptive(light: 0xE3E5EA, dark: 0x2A2F3A)

    // Computed because it derives from `accent`; a stored `let` would freeze the
    // gradient at whichever theme was active on first access.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, zoneInRange], startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// The user-selectable accent palette (Settings → Appearance).
///
/// Only the brand accent changes with the theme — the glucose zone colours are
/// medical semantics and stay fixed. The choice is persisted by `Preferences`
/// under `pref.accentTheme` in the shared App Group defaults, so the app, the
/// widgets and the watch all resolve the same accent.
enum AccentTheme: String, CaseIterable, Identifiable {
    case `default`
    case ocean
    case violet
    case sunset
    case rose
    case forest

    var id: String { rawValue }

    /// The key `Preferences` writes. Duplicated here (rather than referenced) so
    /// Theme keeps compiling in the widget and watch targets, where the app's
    /// `Preferences` type does not exist.
    private static let preferenceKey = "pref.accentTheme"

    /// The theme currently chosen in Settings, falling back to the teal brand.
    static var current: AccentTheme {
        let raw = UserDefaults(suiteName: SharedStore.appGroupIdentifier)?
            .string(forKey: preferenceKey)
        return raw.flatMap(AccentTheme.init(rawValue:)) ?? .default
    }

    var displayName: String {
        switch self {
        case .default: String(localized: "Teal")
        case .ocean: String(localized: "Ocean")
        case .violet: String(localized: "Violet")
        case .sunset: String(localized: "Sunset")
        case .rose: String(localized: "Rose")
        case .forest: String(localized: "Forest")
        }
    }

    /// The light/dark-adaptive brand accent for this theme.
    var accent: Color { Color.adaptive(light: accentHex.light, dark: accentHex.dark) }

    /// The soft tint used behind accent-coloured glyphs and fills.
    var accentSoft: Color { Color.adaptive(light: softHex.light, dark: softHex.dark) }

    /// A single representative colour for swatch circles in pickers.
    var swatch: Color { accent }

    // Hex pairs chosen to hold roughly AA contrast against the app's light
    // (0xF2F3F7) and dark (0x0B0E14) backgrounds: deep, muted tones in light
    // mode and brighter tints in dark mode. Forest is a deep pine on purpose,
    // clearly distinct from `Theme.zoneInRange`'s brighter clinical green.
    private var accentHex: (light: UInt, dark: UInt) {
        switch self {
        case .default: (0x0E9F9A, 0x2FD4CE)
        case .ocean: (0x1668C4, 0x64B6FF)
        case .violet: (0x6A4FC7, 0xAF9BF5)
        case .sunset: (0xC2410C, 0xF59E72)
        case .rose: (0xC13568, 0xF287AE)
        case .forest: (0x22754C, 0x63C793)
        }
    }

    private var softHex: (light: UInt, dark: UInt) {
        switch self {
        case .default: (0xE1F4F3, 0x143A38)
        case .ocean: (0xE3EEFB, 0x16293D)
        case .violet: (0xEDE9F9, 0x272040)
        case .sunset: (0xF9E9E0, 0x3D2418)
        case .rose: (0xF9E6EE, 0x3D1E2B)
        case .forest: (0xE4F1E9, 0x1B3527)
        }
    }
}

extension Color {
    /// A light/dark-adaptive colour from two hex values.
    ///
    /// `UIColor(dynamicProvider:)` exists on iOS but not watchOS, so the watch
    /// (always a dark UI) falls back to the dark value.
    static func adaptive(light: UInt, dark: UInt) -> Color {
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #elseif os(watchOS)
        return Color(hex: dark)
        #else
        return Color(hex: light)
        #endif
    }

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#if canImport(UIKit)
extension Color {
    /// The colour as an uppercase "RRGGBB" hex string (alpha dropped), for
    /// persisting a user-picked colour. Nil if the components can't be read.
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp: (CGFloat) -> Int = { Swift.max(0, Swift.min(255, Int(($0 * 255).rounded()))) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
