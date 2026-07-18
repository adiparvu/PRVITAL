import SwiftUI
import WidgetKit

/// The WidgetKit extension's entry point. This is the single `@main` for the
/// widget process; it groups every widget the extension vends.
///
/// The extension is intentionally lightweight — it renders only from a
/// pre-computed `GlucoseSnapshot` loaded through `SharedStore`, so no medical
/// logic or SwiftData stack ever runs in the widget process.
@main
struct PrvitalWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlucoseWidget()
        GlucoseAccessoryWidget()
    }
}
