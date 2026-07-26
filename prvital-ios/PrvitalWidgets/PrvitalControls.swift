import SwiftUI
import WidgetKit
import AppIntents

/// Control Center quick actions: one tap from anywhere — even the Lock Screen —
/// straight into logging or the emergency card. Users add them from Control
/// Center's gallery (and can bind them to the Action button). Pure launchers:
/// no medical logic runs here, they only deep-link into the app.

/// Opens the quick-entry hub.
struct QuickLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvital.control.log") {
            ControlWidgetButton(action: OpenQuickLogIntent()) {
                Label("Add", systemImage: "drop.circle.fill")
            }
        }
        .displayName("Add")
        .description("Log glucose, a meal or insulin.")
    }
}

/// Opens the emergency card — the screen you hand to a helper.
struct EmergencyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvital.control.emergency") {
            ControlWidgetButton(action: OpenEmergencyIntent()) {
                Label("Emergency card", systemImage: "staroflife.circle.fill")
            }
        }
        .displayName("Emergency card")
        .description("Open the emergency card.")
    }
}

struct OpenQuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Add"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "prvital://log")!))
    }
}

struct OpenEmergencyIntent: AppIntent {
    static let title: LocalizedStringResource = "Emergency card"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "prvital://emergency")!))
    }
}
