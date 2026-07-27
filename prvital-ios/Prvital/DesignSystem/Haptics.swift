import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper over haptic feedback so views call one API and it no-ops where
/// haptics are unavailable.
enum Haptics {
    enum Style { case light, medium, success, warning, selection }

    /// Reads the whole-app haptics switch (Settings → Appearance) from the shared
    /// defaults. Defaults to on when unset, so haptics work before the user ever
    /// opens the setting. Reading here — rather than at every call site — keeps
    /// the single toggle authoritative without threading `Preferences` through.
    private static var isEnabled: Bool {
        (SharedStore.groupDefaults.object(forKey: "pref.hapticsEnabled") as? Bool) ?? true
    }

    @MainActor
    static func play(_ style: Style) {
        #if os(iOS)
        guard isEnabled else { return }
        switch style {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}
