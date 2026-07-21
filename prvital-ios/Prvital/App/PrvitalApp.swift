import SwiftUI
import SwiftData

@main
struct PrvitalApp: App {
    @State private var environment = AppEnvironment.live()

    init() {
        // Handles notification action taps (acknowledging critical-low alarm
        // repeats). Must be attached before the app finishes launching so a
        // response that cold-starts the app is not missed.
        CriticalAlarmNotificationDelegate.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
                .tint(Theme.accent)
                .task { environment.bootstrap() }
        }
        .backgroundTask(.appRefresh(AppEnvironment.backgroundRefreshIdentifier)) { [environment] in
            await environment.performBackgroundRefresh()
        }
    }
}

/// Gates the app behind first-run consent onboarding, then shows the tab shell.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var showQuickEntry = false
    @State private var showWhatsNew = false

    var body: some View {
        MainTabView()
            .onAppear {
                showOnboarding = !env.consent.hasCompletedOnboarding
                if showOnboarding {
                    // A brand-new install is meeting every feature for the first
                    // time, so the "What's new" tour would be noise on top of
                    // onboarding. Stamp the current version; the tour first
                    // auto-presents after an update.
                    env.preferences.lastSeenWhatsNewVersion = WhatsNewTour.currentVersion
                } else if env.preferences.lastSeenWhatsNewVersion != WhatsNewTour.currentVersion {
                    showWhatsNew = true
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showWhatsNew, onDismiss: {
                // Swiping the sheet away counts as seen too, so it never nags.
                env.preferences.lastSeenWhatsNewVersion = WhatsNewTour.currentVersion
            }) {
                WhatsNewView()
            }
            .sheet(isPresented: $showQuickEntry) { QuickEntrySheet() }
            .onOpenURL { url in
                // Deep link from the widget: open the quick-entry hub.
                if url.scheme == "prvital", url.host == "log" {
                    showQuickEntry = true
                }
            }
            // Live foreground polling: while the app is open, refresh connected
            // CGM sources on the user's chosen cadence (default ~1 min) so the
            // reading stays current without waiting for a pull-to-refresh.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                let seconds = max(15, env.preferences.liveSyncSeconds)
                guard env.preferences.liveSyncSeconds > 0 else { return }
                while !Task.isCancelled {
                    await env.sync.refreshLatest()
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
    }
}

/// The five primary destinations. History, Charts, Statistics and Export are
/// reached from within Insights; the Calendar month view is reached from the
/// Journal; quick entry is presented from Dashboard/Journal.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "drop.fill") }
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            LearnView()
                .tabItem { Label("Learn", systemImage: "book.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
