import SwiftUI
import Foundation

/// The Apple Watch companion's entry point.
///
/// The watch app is deliberately thin: it renders only from a pre-computed
/// `GlucoseSnapshot` delivered by the phone over WatchConnectivity (or loaded
/// from the shared App Group on a cold launch), and it can send quick insulin /
/// carb entries back to the phone. No medical logic and no SwiftData stack ever
/// runs on the watch — every value is a pre-formatted string in the snapshot.
@main
struct PrvitalWatchApp: App {
    /// Owns the live snapshot and the connectivity wiring for the whole app.
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}

/// Observable holder for the latest `GlucoseSnapshot`.
///
/// It seeds itself from the shared store so the very first frame shows real
/// data, then subscribes to fresh snapshots pushed from the phone. Main-actor
/// isolated because it wires up the `@MainActor WatchSessionManager`; snapshot
/// updates are delivered on the main actor.
@MainActor
@Observable
final class WatchModel {
    /// The display-ready snapshot currently shown across every page.
    var snapshot: GlucoseSnapshot

    init() {
        snapshot = SharedStore.load()
        WatchSessionManager.shared.onSnapshot = { [weak self] snapshot in
            self?.snapshot = snapshot
        }
        WatchSessionManager.shared.activate()
    }
}
