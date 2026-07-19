import SwiftUI
import WidgetKit

/// The watchOS complication bundle — the `@main` for the watch widget process.
///
/// It reuses the shared accessory glucose widget (`GlucoseAccessoryWidget`,
/// circular / rectangular / inline families, which on watchOS are complication
/// families) and the shared `GlucoseProvider`. Like the phone widgets it renders
/// purely from the `GlucoseSnapshot` published to the App Group, so no medical
/// logic or SwiftData stack runs in the watch widget process.
@main
struct PrvitalWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlucoseAccessoryWidget()
    }
}
