import SwiftUI
import SwiftData

@main
struct DiabetesJournalApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
                .tint(Theme.accent)
                .task { environment.bootstrap() }
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
/// reached from within Insights; quick entry is presented from Dashboard/Journal.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "drop.fill") }
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
