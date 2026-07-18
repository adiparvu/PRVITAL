import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper over haptic feedback so views call one API and it no-ops where
/// haptics are unavailable.
enum Haptics {
    enum Style { case light, medium, success, warning, selection }

    @MainActor
    static func play(_ style: Style) {
        #if os(iOS)
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
