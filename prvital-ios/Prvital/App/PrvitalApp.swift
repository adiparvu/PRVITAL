import SwiftUI
import SwiftData

@main
struct PrvitalApp: App {
    @State private var environment = AppEnvironment.live()

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
    @State private var showOnboarding = false

    var body: some View {
        MainTabView()
            .onAppear { showOnboarding = !env.consent.hasCompletedOnboarding }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
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
