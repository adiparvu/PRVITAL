import SwiftUI
#if canImport(UIKit)
import UIKit
import ImageIO
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
    /// How strongly the photo is darkened for legibility (0…0.7).
    static let photoDimmingKey = "pref.backgroundPhotoDimming"
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

    static var currentPhotoDimming: Double {
        (defaults?.object(forKey: photoDimmingKey) as? Double) ?? 0.3
    }
}

// MARK: - The background view + screen modifier

/// Renders the currently-chosen app background. Falls back to the standard
/// surface, so it is always safe to place behind any screen.
struct AppBackgroundView: View {
    var kind: AppBackgroundKind = .current
    var gradient: BackgroundGradient = AppBackgroundKind.currentGradient
    var photoData: Data? = AppBackgroundKind.currentPhotoData
    var photoDimming: Double = AppBackgroundKind.currentPhotoDimming

    var body: some View {
        switch kind {
        case .standard:
            standardBackground
        case .gradient:
            gradient.gradient
        case .photo:
            photoView
        }
    }

    /// The default background. Not a flat fill but a whisper-soft wash — a faint
    /// accent glow at the top and a hint of the in-range green at the bottom over
    /// the base surface — so the frosted-glass cards and settings rows layered
    /// above always have some depth to refract. Without this, glass over a flat
    /// colour just reads as flat grey, which is exactly the "this isn't liquid
    /// glass" complaint. Subtle enough that text legibility is untouched.
    private var standardBackground: some View {
        ZStack {
            Theme.background
            LinearGradient(
                colors: [Theme.accent.opacity(0.14), .clear],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
            LinearGradient(
                colors: [.clear, Theme.zoneInRange.opacity(0.07)],
                startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var photoView: some View {
        #if canImport(UIKit)
        // The standard wash paints instantly; the decoded photo fades in over it
        // once the background decode lands. The previous code ran
        // `UIImage(data:)` inside body — re-inflating a multi-megapixel photo on
        // the main thread on every render of every tab background, which was the
        // single biggest cause of the "switching tabs lags" feel.
        ZStack {
            standardBackground
            if let image = BackgroundPhotoStore.shared.image(matching: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // A neutral scrim at the user's chosen strength keeps cards
                    // and text legible over any photo (Settings → Background).
                    .overlay(Color.black.opacity(photoDimming))
                    .transition(.opacity)
            }
        }
        .task(id: photoData) { BackgroundPhotoStore.shared.prepare(photoData) }
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

#if canImport(UIKit)
/// Decodes the user's background photo ONCE, off the main thread, downsampled to
/// screen scale via ImageIO — and hands every tab the same cached image.
///
/// `UIImage(data:)` in a view body decoded the full-resolution photo on the main
/// thread on every render; with a 12-megapixel wallpaper that alone froze every
/// tab switch for a beat. Here the decode happens on a detached task, produces a
/// bitmap no larger than ~1600px, and is cached until the user picks a new photo.
@MainActor
@Observable
final class BackgroundPhotoStore {
    static let shared = BackgroundPhotoStore()

    private(set) var decoded: UIImage?
    /// Average luminance (0 = black … 1 = white) of the decoded photo, so the
    /// app can pick light or dark text over it. Nil until a decode lands.
    private(set) var averageLuminance: Double?
    private var decodedKey: Int?
    private var pendingKey: Int?

    /// The cached image when it matches `data`; nil while (re)decoding.
    func image(matching data: Data?) -> UIImage? {
        guard let data, decodedKey == Self.key(for: data) else { return nil }
        return decoded
    }

    /// Kicks a background decode unless `data` is already cached or in flight.
    func prepare(_ data: Data?) {
        guard let data else {
            decoded = nil
            averageLuminance = nil
            decodedKey = nil
            pendingKey = nil
            return
        }
        let key = Self.key(for: data)
        guard key != decodedKey, key != pendingKey else { return }
        pendingKey = key
        Task.detached(priority: .userInitiated) {
            let image = Self.downsample(data)
            let luminance = image.flatMap(Self.luminance(of:))
            await MainActor.run {
                guard self.pendingKey == key else { return }
                self.pendingKey = nil
                self.decodedKey = key
                self.averageLuminance = luminance
                withAnimation(.easeIn(duration: 0.2)) { self.decoded = image }
            }
        }
    }

    /// Cheap fingerprint: length plus a byte sample. The photo only changes when
    /// the user picks a new one, so this never needs to be cryptographic.
    private nonisolated static func key(for data: Data) -> Int {
        var hash = data.count
        for byte in data.suffix(32) { hash = hash &* 31 &+ Int(byte) }
        return hash
    }

    /// ImageIO thumbnailing: decodes straight to a screen-sized bitmap instead of
    /// inflating the full-resolution photo just to scale it down every frame.
    private nonisolated static func downsample(_ data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600.0
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Draws the image into a single pixel — the GPU-free way to average it —
    /// and returns its relative luminance (0…1).
    private nonisolated static func luminance(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = Double(pixel[0]) / 255, g = Double(pixel[1]) / 255, b = Double(pixel[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
#endif
