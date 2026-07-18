import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Design tokens for Diabetes Journal.
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

    // Brand accent — a medical teal.
    static let accent = Color.adaptive(light: 0x0E9F9A, dark: 0x2FD4CE)
    static let accentSoft = Color.adaptive(light: 0xE1F4F3, dark: 0x143A38)

    // Glucose zone colours (green → yellow → orange → red).
    static let zoneInRange = Color.adaptive(light: 0x2FB86B, dark: 0x34D07A)
    static let zoneHigh = Color.adaptive(light: 0xE0A100, dark: 0xF5C242)   // yellow
    static let zoneWarning = Color.adaptive(light: 0xE8730C, dark: 0xF7913D) // orange
    static let zoneCritical = Color.adaptive(light: 0xD64550, dark: 0xF2626B) // red

    static let hairline = Color.adaptive(light: 0xE3E5EA, dark: 0x2A2F3A)

    static let brandGradient = LinearGradient(
        colors: [accent, zoneInRange], startPoint: .topLeading, endPoint: .bottomTrailing
    )
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
