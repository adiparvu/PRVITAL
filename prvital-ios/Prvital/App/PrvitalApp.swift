import SwiftUI
import SwiftData

@main
struct PrvitalApp: App {
    @State private var environment = AppEnvironment.live()
    @State private var language = LanguageManager.shared

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
                // Instant in-app language switch: changing `\.locale` re-resolves
                // every `Text` in place — no restart, and crucially no tree rebuild,
                // so the user stays on whatever screen they're on (picking a
                // language no longer bounces them back to the first tab). Strings
                // that resolve from runtime values instead of compile-time `Text`
                // literals go through `PrvitalString`, which reads the chosen
                // language directly.
                .environment(\.locale, language.locale)
                // Only the accent theme keys the root identity: `Theme.accent` is a
                // global read (not observed), so bumping identity when it changes is
                // what repaints the tab-bar tint and every `Theme.accent` glyph at
                // once. Language is deliberately NOT in the key — see above.
                .id(environment.preferences.accentThemeRaw)
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
    @State private var showEmergency = false
    /// A specific editor requested by a deep link's path (prvital://log/meal…).
    @State private var deepLinkEditor: EntryEditorKind?
    @State private var showWhatsNew = false

    /// Follows the system Dynamic Type when the user leaves "Use system size" on;
    /// otherwise clamps the app to their chosen size with a degenerate range.
    private var typeRange: ClosedRange<DynamicTypeSize> {
        if env.preferences.useSystemTextSize { return .xSmall ... .accessibility5 }
        let size = env.preferences.textSize.dynamicTypeSize
        return size ... size
    }

    var body: some View {
        MainTabView()
            .preferredColorScheme(env.preferences.themeMode.colorScheme)
            .dynamicTypeSize(typeRange)
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
                // Deep links from widgets / Control Center controls. The path
                // picks the exact editor (prvital://log/meal → the carb editor)
                // — it used to be ignored, so every Island button opened the
                // same generic Add sheet (audit finding).
                guard url.scheme == "prvital" else { return }
                switch url.host {
                case "log":
                    switch url.pathComponents.dropFirst().first {
                    case "glucose": deepLinkEditor = .glucose
                    case "insulin": deepLinkEditor = .insulin
                    case "meal", "carbs": deepLinkEditor = .carbs
                    default: showQuickEntry = true
                    }
                case "emergency": showEmergency = true
                default: break
                }
            }
            .sheet(item: $deepLinkEditor) { EntryEditor(kind: $0) }
            .sheet(isPresented: $showEmergency) {
                NavigationStack { EmergencyCardView() }
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
            // Republish the widget snapshot from the current store every time the
            // app is foregrounded, and force a timeline reload. This is the
            // reliable cure for a widget stuck on "No data" after an update or a
            // CSV import: the shared snapshot file is rewritten with real data and
            // the widgets refresh — without depending on a cold launch or on a
            // live CGM source being connected (a CSV-only user never syncs).
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                env.snapshots.refresh()
                env.snapshots.reloadWidgets()
                // Keep the audit trail lean without waiting for a cold launch —
                // throttled internally to at most once a day.
                env.audit.pruneIfDue()
                // Refresh the Sunday notification's headline with the current
                // top insight (no-op unless the user opted in).
                env.rearmWeeklyInsight()
                // Re-arm the ~15-minute background sync on every activation.
                // Submitting is idempotent (same identifier replaces), and
                // without this the chain silently dies whenever iOS discards
                // the pending request — after which widgets and alerts only
                // updated while the app was open.
                env.scheduleBackgroundRefresh()
                // Arms Health background delivery if consent arrived after
                // bootstrap (e.g. granted during onboarding). No-op once armed.
                env.startHealthKitBackgroundDelivery()
            }
    }
}

/// Applies the user's chosen app background (Settings → Appearance → Background)
/// behind a tab screen. Reads the live preference through the environment, so
/// switching gradient/photo updates every tab at once. Lives in the app target
/// (it depends on `AppEnvironment`), unlike the target-safe `AppBackgroundView`.
struct PrvitalTabBackground: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.background {
            AppBackgroundView(
                kind: env.preferences.backgroundKind,
                gradient: env.preferences.backgroundGradient,
                photoData: env.preferences.backgroundPhotoData
            )
            .ignoresSafeArea()
        }
    }
}

extension View {
    /// Paints the chosen app background behind a primary tab screen.
    func prvitalTabBackground() -> some View { modifier(PrvitalTabBackground()) }
}

/// The five primary destinations. History, Charts, Statistics and Export are
/// reached from within Insights; the Calendar month view is reached from the
/// Journal; quick entry is presented from Dashboard/Journal.
/// The app's tab shell: four real destinations plus a centre "+" that never
/// selects — it opens the quick-entry hub and snaps back, like a floating
/// action button living in the tab bar (the Prvio pattern the user asked for).
/// Learn lost its tab (rarely visited; lessons already surface contextually on
/// the dashboard) and now lives behind the book button on Insights.
struct MainTabView: View {
    private enum MainTab: Hashable { case home, journal, add, insights, settings }
    @State private var selection: MainTab = .home
    @State private var showQuickAdd = false

    var body: some View {
        // Icon-only items (device feedback: "make the tabs in this style") —
        // the floating glass pill reads as five clean glyphs, the selected one
        // carried by the system's capsule highlight. No Text in a tab item
        // means the bar centres the icon alone; the accessibility labels keep
        // VoiceOver speaking the destination names.
        TabView(selection: $selection) {
            DashboardView()
                .tabItem {
                    Image(systemName: "drop.fill")
                        .accessibilityLabel("Dashboard")
                }
                .tag(MainTab.home)
            JournalView()
                .tabItem {
                    Image(systemName: "book.closed.fill")
                        .accessibilityLabel("Journal")
                }
                .tag(MainTab.journal)
            Color.clear
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel("Add")
                }
                .tag(MainTab.add)
            InsightsView()
                .tabItem {
                    Image(systemName: "chart.xyaxis.line")
                        .accessibilityLabel("Insights")
                }
                .tag(MainTab.insights)
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                        .accessibilityLabel("Settings")
                }
                .tag(MainTab.settings)
        }
        // The bar tucks away while scrolling and returns on touch — content
        // breathes on every tab.
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selection) { old, new in
            // "+" acts, it doesn't navigate: bounce straight back to the tab the
            // user was on and raise the quick-entry hub.
            if new == .add {
                selection = old
                Haptics.play(.light)
                showQuickAdd = true
            }
        }
        .sheet(isPresented: $showQuickAdd) { QuickEntrySheet() }
    }
}
