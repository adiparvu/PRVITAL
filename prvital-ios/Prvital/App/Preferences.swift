import Foundation
import Observation

/// User-facing preferences, persisted in the shared App Group defaults so the
/// widgets and watch read the same unit and target range.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        self.glucoseUnit = Self.readUnit(self.defaults)
        self.thresholds = Self.readThresholds(self.defaults)
        self.reminders = Self.readReminders(self.defaults)
        self.nightscout = Self.readNightscout(self.defaults)
        self.bolusParameters = Self.readBolus(self.defaults)
        self.alerts = Self.readAlerts(self.defaults)
        self.community = Self.readCommunity(self.defaults)
        self.glucoseSchedule = Self.readGlucoseSchedule(self.defaults)
        self.glucoseGoals = Self.readGlucoseGoals(self.defaults)
        self.ringGoals = Self.readRingGoals(self.defaults)
        self.activityGoals = Self.readActivityGoals(self.defaults)
        self.periodTIRTargets = Self.readPeriodTIRTargets(self.defaults)
        self.chartEventKinds = Self.readChartEventKinds(self.defaults)
        self.medicationPlan = Self.readMedicationPlan(self.defaults)
        self.liveSyncSeconds = (self.defaults.object(forKey: Keys.liveSync) as? Int) ?? 60
        self.postprandialWindowHours = (self.defaults.object(forKey: Keys.postprandialWindow) as? Int) ?? 3
        self.sickDayEnabled = self.defaults.bool(forKey: Keys.sickDayEnabled)
        self.sickDayStartedAt = self.defaults.object(forKey: Keys.sickDayStartedAt) as? Date
        self.emergencyInfo = Self.readEmergencyInfo(self.defaults)
        self.criticalAlarm = Self.readCriticalAlarm(self.defaults)
        self.alertSounds = Self.readAlertSounds(self.defaults)
        self.weeklyDigestEnabled = self.defaults.bool(forKey: Keys.weeklyDigest)
        self.weeklyInsightEnabled = self.defaults.bool(forKey: Keys.weeklyInsight)
        self.nightscoutUploadEnabled = self.defaults.bool(forKey: Keys.nightscoutUpload)
        self.journalCardDensityRaw = self.defaults.string(forKey: Keys.journalCardDensity) ?? "standard"
        self.lastSeenWhatsNewVersion = self.defaults.string(forKey: Keys.lastSeenWhatsNew) ?? ""
        self.themeModeRaw = self.defaults.string(forKey: Keys.themeMode) ?? ThemeMode.system.rawValue
        self.useSystemTextSize = (self.defaults.object(forKey: Keys.useSystemTextSize) as? Bool) ?? true
        self.textSizeRaw = self.defaults.string(forKey: Keys.textSize) ?? AppTextSize.large.rawValue
        self.hapticsEnabled = (self.defaults.object(forKey: Keys.hapticsEnabled) as? Bool) ?? true
        self.appLockEnabled = (self.defaults.object(forKey: Keys.appLock) as? Bool) ?? false
        self.morningReportEnabled = (self.defaults.object(forKey: Keys.morningReport) as? Bool) ?? false
        self.morningReportMinutes = (self.defaults.object(forKey: Keys.morningReportTime) as? Int) ?? 450
        self.showDailyCompanion = (self.defaults.object(forKey: Keys.showDailyCompanion) as? Bool) ?? true
        self.showContextualLessons = (self.defaults.object(forKey: Keys.showContextualLessons) as? Bool) ?? true
        self.minimalistIcons = (self.defaults.object(forKey: Keys.minimalistIcons) as? Bool) ?? false
        self.showYesterdayShadow = (self.defaults.object(forKey: Keys.showYesterdayShadow) as? Bool) ?? true
        self.dashboardCardOrder = self.defaults.stringArray(forKey: Keys.dashboardCardOrder) ?? []
        self.dashboardHiddenCards = self.defaults.stringArray(forKey: Keys.dashboardHiddenCards) ?? []
        self.backgroundKindRaw = self.defaults.string(forKey: Keys.backgroundKind) ?? AppBackgroundKind.standard.rawValue
        self.backgroundGradientRaw = self.defaults.string(forKey: Keys.backgroundGradient) ?? BackgroundGradient.aurora.rawValue
        self.backgroundPhotoDimming = (self.defaults.object(forKey: Keys.backgroundPhotoDimming) as? Double) ?? 0.3
    }

    /// How much detail the journal's day cards show ("compact" / "standard" /
    /// "detailed"), in the spirit of a presets picker. Raw string so the enum can
    /// live beside the view that owns it.
    var journalCardDensityRaw: String {
        didSet { defaults.set(journalCardDensityRaw, forKey: Keys.journalCardDensity) }
    }

    /// The last app version whose "What's new" tour the user has seen. Empty
    /// until the first tour is shown.
    var lastSeenWhatsNewVersion: String {
        didSet { defaults.set(lastSeenWhatsNewVersion, forKey: Keys.lastSeenWhatsNew) }
    }

    var glucoseUnit: GlucoseUnit {
        didSet { defaults.set(glucoseUnit.rawValue, forKey: Keys.unit) }
    }

    var thresholds: GlucoseThresholds {
        didSet { if let data = try? JSONEncoder().encode(thresholds) { defaults.set(data, forKey: Keys.thresholds) } }
    }

    var reminders: ReminderPreferences {
        didSet { if let data = try? JSONEncoder().encode(reminders) { defaults.set(data, forKey: Keys.reminders) } }
    }

    /// Self-hosted Nightscout connection. Empty until the user configures it in
    /// Settings → Sources → Nightscout.
    var nightscout: NightscoutConfig {
        didSet { if let data = try? JSONEncoder().encode(nightscout) { defaults.set(data, forKey: Keys.nightscout) } }
    }

    /// Personal therapy settings for the (opt-in) bolus calculator.
    var bolusParameters: BolusParameters {
        didSet { if let data = try? JSONEncoder().encode(bolusParameters) { defaults.set(data, forKey: Keys.bolus) } }
    }

    /// Reactive glucose alert settings (opt-in, off by default).
    var alerts: AlertPreferences {
        didSet { if let data = try? JSONEncoder().encode(alerts) { defaults.set(data, forKey: Keys.alerts) } }
    }

    /// Community leaderboard participation (opt-in; pseudonym + points only).
    var community: CommunityPreferences {
        didSet { if let data = try? JSONEncoder().encode(community) { defaults.set(data, forKey: Keys.community) } }
    }

    /// The user's chosen glucose-logging routine (times of day + optional
    /// reminders).
    var glucoseSchedule: GlucoseSchedule {
        didSet { if let data = try? JSONEncoder().encode(glucoseSchedule) { defaults.set(data, forKey: Keys.glucoseSchedule) } }
    }

    /// Opt-in Time-in-Range and A1c goals with a motivational streak (off by
    /// default). Stored under its own key so enabling it never disturbs any
    /// existing preference.
    var glucoseGoals: GlucoseGoals {
        didSet { if let data = try? JSONEncoder().encode(glucoseGoals) { defaults.set(data, forKey: Keys.glucoseGoals) } }
    }

    /// Goals for the daily activity rings (active-minutes target and sensor
    /// uptime target). The in-range ring reuses `glucoseGoals.targetTIRFraction`,
    /// so this only owns the two ring-specific numbers.
    var ringGoals: RingGoals {
        didSet { if let data = try? JSONEncoder().encode(ringGoals) { defaults.set(data, forKey: Keys.ringGoals) } }
    }

    /// Editable daily targets for the Health hub's activity rings (steps, move
    /// energy, exercise minutes) and the streaks built on them.
    var activityGoals: ActivityGoals {
        didSet { if let data = try? JSONEncoder().encode(activityGoals) { defaults.set(data, forKey: Keys.activityGoals) } }
    }

    /// Optional per-time-of-day Time-in-Range targets. When disabled, every
    /// period uses the single `glucoseGoals` target; when enabled, each part of
    /// the day can carry its own goal (e.g. a looser overnight target). Stored
    /// under its own key, so this is a purely additive, migration-safe change.
    var periodTIRTargets: PeriodTIRTargets {
        didSet { if let data = try? JSONEncoder().encode(periodTIRTargets) { defaults.set(data, forKey: Keys.periodTIRTargets) } }
    }

    /// Which non-glucose event kinds are drawn as markers on the glucose chart.
    var chartEventKinds: Set<ChartEventKind> {
        didSet { if let data = try? JSONEncoder().encode(chartEventKinds) { defaults.set(data, forKey: Keys.chartEventKinds) } }
    }

    /// The user's non-insulin medication schedule (names, doses, times). Drives
    /// reminders and the adherence view; empty until the user adds a medication.
    var medicationPlan: MedicationPlan {
        didSet { if let data = try? JSONEncoder().encode(medicationPlan) { defaults.set(data, forKey: Keys.medicationPlan) } }
    }

    /// How often (seconds) to poll connected CGM sources while the app is open.
    /// 0 disables live polling. Default 60s, which matches a Libre's per-minute
    /// cadence; Dexcom publishes every 5 minutes so extra polls simply no-op.
    var liveSyncSeconds: Int {
        didSet { defaults.set(liveSyncSeconds, forKey: Keys.liveSync) }
    }

    /// How many hours after a meal the post-meal response page and markers span
    /// (1–4, mirroring the classic "postprandial comparison" setting). Clamped
    /// on read so a stray value can't produce an empty window.
    var postprandialWindowHours: Int {
        didSet { defaults.set(min(4, max(1, postprandialWindowHours)), forKey: Keys.postprandialWindow) }
    }

    /// Whether the user has turned on sick-day mode. When on, the dashboard shows
    /// a sick-day guidance banner. Off by default and stored under its own key, so
    /// adding it is a purely additive, migration-safe change (like `glucoseGoals`).
    var sickDayEnabled: Bool {
        didSet { defaults.set(sickDayEnabled, forKey: Keys.sickDayEnabled) }
    }

    /// When the current sick-day episode began, set the moment sick-day mode is
    /// turned on and cleared when it's turned off. Optional so "not in a sick day"
    /// is simply absent.
    var sickDayStartedAt: Date? {
        didSet {
            if let sickDayStartedAt { defaults.set(sickDayStartedAt, forKey: Keys.sickDayStartedAt) }
            else { defaults.removeObject(forKey: Keys.sickDayStartedAt) }
        }
    }

    /// The emergency card: contacts, where the glucagon is kept, and any note a
    /// helper should read. Empty by default; stored under its own key.
    var emergencyInfo: EmergencyInfo {
        didSet { if let data = try? JSONEncoder().encode(emergencyInfo) { defaults.set(data, forKey: Keys.emergencyInfo) } }
    }

    /// Critical-low alarm escalation (repeat-until-acknowledged). Off by default.
    var criticalAlarm: CriticalAlarmPreferences {
        didSet { if let data = try? JSONEncoder().encode(criticalAlarm) { defaults.set(data, forKey: Keys.criticalAlarm) } }
    }

    /// Per-category notification sound choices (critical / important /
    /// reminders). Persisted as JSON in the shared defaults so the static
    /// delivery sites (`AlertSoundStore`) read the same source of truth.
    var alertSounds: AlertSoundPreferences {
        didSet { if let data = try? JSONEncoder().encode(alertSounds) { defaults.set(data, forKey: Keys.alertSounds) } }
    }

    /// Monday-morning "your week in review" summary. Off by default.
    var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Keys.weeklyDigest) }
    }

    /// Sunday-evening notification carrying the week's top insight headline.
    /// Off by default.
    var weeklyInsightEnabled: Bool {
        didSet { defaults.set(weeklyInsightEnabled, forKey: Keys.weeklyInsight) }
    }

    /// Mirror the user's entries up to their own Nightscout site. Off by default.
    /// A separate key (not a field on `NightscoutConfig`) so enabling it can
    /// never invalidate an already-stored connection config.
    var nightscoutUploadEnabled: Bool {
        didSet { defaults.set(nightscoutUploadEnabled, forKey: Keys.nightscoutUpload) }
    }

    // Both accent values live in `AccentPreference`, the observable store that
    // `Theme.accent` itself reads. Forwarding rather than duplicating is what
    // keeps a colour change repainting every `Theme.accent` in the app the
    // moment it is written — no root-identity bump, no lost screen.

    /// The chosen accent theme's raw identifier ("default" = the teal brand).
    var accentThemeRaw: String {
        get { AccentPreference.shared.themeRaw }
        set { AccentPreference.shared.themeRaw = newValue }
    }

    /// The custom accent colour (0xRRGGBB), used when the theme is "custom".
    var accentCustomHex: Int {
        get { AccentPreference.shared.customHex }
        set { AccentPreference.shared.customHex = newValue }
    }

    // MARK: Appearance (theme mode, text size, haptics, background)

    /// Light / dark / system. Stored raw so `ThemeMode` (a DesignSystem type)
    /// stays the single source of truth for the mapping.
    var themeModeRaw: String {
        didSet { defaults.set(themeModeRaw, forKey: Keys.themeMode) }
    }
    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    /// When true, Prvital follows the system Dynamic Type size; when false, it
    /// uses `textSize` as a fixed override for the app only.
    var useSystemTextSize: Bool {
        didSet { defaults.set(useSystemTextSize, forKey: Keys.useSystemTextSize) }
    }
    var textSizeRaw: String {
        didSet { defaults.set(textSizeRaw, forKey: Keys.textSize) }
    }
    var textSize: AppTextSize {
        get { AppTextSize(rawValue: textSizeRaw) ?? .large }
        set { textSizeRaw = newValue.rawValue }
    }

    /// The whole-app haptics switch. `Haptics.play` reads the same key, so
    /// turning this off silences every haptic without touching call sites.
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    /// Whether the Dashboard shows the supportive daily companion card. On by
    /// default; users who prefer a plainer dashboard can switch it off.
    var showDailyCompanion: Bool {
        didSet { defaults.set(showDailyCompanion, forKey: Keys.showDailyCompanion) }
    }

    /// Whether the Dashboard surfaces the contextual education card ("Because you
    /// had a low earlier → Understanding lows"). On by default; can be switched off.
    var showContextualLessons: Bool {
        didSet { defaults.set(showContextualLessons, forKey: Keys.showContextualLessons) }
    }

    /// Minimalist iconography: monochrome, unfilled glyphs instead of the tinted,
    /// filled circles — a cleaner, Apple-plain look. Off by default.
    var minimalistIcons: Bool {
        didSet { defaults.set(minimalistIcons, forKey: Keys.minimalistIcons) }
    }

    /// Draw yesterday's curve as a faint ghost under today's trend chart.
    var showYesterdayShadow: Bool {
        didSet { defaults.set(showYesterdayShadow, forKey: Keys.showYesterdayShadow) }
    }

    /// Require Face ID / passcode whenever the app returns to the foreground.
    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Keys.appLock) }
    }

    /// The wake-up overnight summary notification, and when it arrives
    /// (minutes from midnight; 450 = 07:30).
    var morningReportEnabled: Bool {
        didSet { defaults.set(morningReportEnabled, forKey: Keys.morningReport) }
    }
    var morningReportMinutes: Int {
        didSet { defaults.set(morningReportMinutes, forKey: Keys.morningReportTime) }
    }

    /// The dashboard deck's card order (raw `DashboardCard` values). Empty means
    /// the default order; unknown/new cards append automatically on resolve.
    var dashboardCardOrder: [String] {
        didSet { defaults.set(dashboardCardOrder, forKey: Keys.dashboardCardOrder) }
    }

    /// Cards the user switched off (raw values). The companion and lessons cards
    /// keep their own dedicated toggles instead of living in this set.
    var dashboardHiddenCards: [String] {
        didSet { defaults.set(dashboardHiddenCards, forKey: Keys.dashboardHiddenCards) }
    }

    /// Background: standard surface, a gradient preset, or the user's photo.
    var backgroundKindRaw: String {
        didSet { defaults.set(backgroundKindRaw, forKey: Keys.backgroundKind) }
    }
    var backgroundKind: AppBackgroundKind {
        get { AppBackgroundKind(rawValue: backgroundKindRaw) ?? .standard }
        set { backgroundKindRaw = newValue.rawValue }
    }
    var backgroundGradientRaw: String {
        didSet { defaults.set(backgroundGradientRaw, forKey: Keys.backgroundGradient) }
    }
    var backgroundGradient: BackgroundGradient {
        get { BackgroundGradient(rawValue: backgroundGradientRaw) ?? .aurora }
        set { backgroundGradientRaw = newValue.rawValue }
    }
    /// The chosen background photo, if any (JPEG/PNG data). The bytes live in a
    /// FILE in the App Group container (via `BackgroundPhotoStore`) — never in
    /// `UserDefaults`: megabytes of photo inside the shared plist made every
    /// preference write rewrite the whole file, and every widget-process write
    /// invalidate and re-parse it, which the app felt as lag on every screen.
    var backgroundPhotoData: Data? {
        get { BackgroundPhotoStore.shared.data }
        set { BackgroundPhotoStore.shared.setPhoto(newValue) }
    }

    /// How strongly the background photo is darkened for legibility (0…0.7).
    var backgroundPhotoDimming: Double {
        didSet { defaults.set(backgroundPhotoDimming, forKey: Keys.backgroundPhotoDimming) }
    }

    let activityDurations: [Int] = [15, 30, 45, 60, 90, 120]

    // MARK: Persistence

    private enum Keys {
        static let unit = "pref.glucoseUnit"
        static let thresholds = "pref.thresholds"
        static let reminders = "pref.reminders"
        static let nightscout = "pref.nightscout"
        static let bolus = "pref.bolusParameters"
        static let alerts = "pref.alerts"
        static let community = "pref.community"
        static let glucoseSchedule = "pref.glucoseSchedule"
        static let glucoseGoals = "pref.glucoseGoals"
        static let ringGoals = "pref.ringGoals"
        static let activityGoals = "pref.activityGoals"
        static let periodTIRTargets = "pref.periodTIRTargets"
        static let chartEventKinds = "pref.chartEventKinds"
        static let medicationPlan = "pref.medicationPlan"
        static let liveSync = "pref.liveSyncSeconds"
        static let postprandialWindow = "pref.postprandialWindowHours"
        static let sickDayEnabled = "pref.sickDayEnabled"
        static let sickDayStartedAt = "pref.sickDayStartedAt"
        static let emergencyInfo = "pref.emergencyInfo"
        static let criticalAlarm = "pref.criticalAlarm"
        static let weeklyDigest = "pref.weeklyDigestEnabled"
        static let weeklyInsight = "pref.weeklyInsightEnabled"
        /// Must match `AlertSoundStore.key` (AlertSounds.swift).
        static let alertSounds = "pref.alertSounds"
        static let nightscoutUpload = "pref.nightscoutUploadEnabled"
        static let accentTheme = "pref.accentTheme"
        static let journalCardDensity = "pref.journalCardDensity"
        static let lastSeenWhatsNew = "pref.lastSeenWhatsNewVersion"
        static let themeMode = ThemeMode.preferenceKey
        static let useSystemTextSize = "pref.useSystemTextSize"
        static let textSize = AppTextSize.preferenceKey
        static let hapticsEnabled = "pref.hapticsEnabled"
        static let appLock = "pref.appLockEnabled"
        static let morningReport = "pref.morningReportEnabled"
        static let morningReportTime = "pref.morningReportMinutes"
        static let showDailyCompanion = "pref.showDailyCompanion"
        static let showContextualLessons = "pref.showContextualLessons"
        static let minimalistIcons = "pref.minimalistIcons"
        static let showYesterdayShadow = "pref.showYesterdayShadow"
        static let dashboardCardOrder = "pref.dashboardCardOrder"
        static let dashboardHiddenCards = "pref.dashboardHiddenCards"
        static let backgroundKind = AppBackgroundKind.preferenceKey
        static let backgroundGradient = BackgroundGradient.preferenceKey
        static let backgroundPhoto = AppBackgroundKind.photoKey
        static let backgroundPhotoDimming = AppBackgroundKind.photoDimmingKey
    }

    private static func readUnit(_ d: UserDefaults) -> GlucoseUnit {
        d.string(forKey: Keys.unit).flatMap(GlucoseUnit.init(rawValue:)) ?? .mgdL
    }
    private static func readThresholds(_ d: UserDefaults) -> GlucoseThresholds {
        guard let data = d.data(forKey: Keys.thresholds),
              let value = try? JSONDecoder().decode(GlucoseThresholds.self, from: data)
        else { return .standard }
        return value
    }
    private static func readReminders(_ d: UserDefaults) -> ReminderPreferences {
        guard let data = d.data(forKey: Keys.reminders),
              let value = try? JSONDecoder().decode(ReminderPreferences.self, from: data)
        else { return .default }
        return value
    }
    private static func readNightscout(_ d: UserDefaults) -> NightscoutConfig {
        guard let data = d.data(forKey: Keys.nightscout),
              let value = try? JSONDecoder().decode(NightscoutConfig.self, from: data)
        else { return .empty }
        return value
    }
    private static func readBolus(_ d: UserDefaults) -> BolusParameters {
        guard let data = d.data(forKey: Keys.bolus),
              let value = try? JSONDecoder().decode(BolusParameters.self, from: data)
        else { return .default }
        return value
    }
    private static func readAlerts(_ d: UserDefaults) -> AlertPreferences {
        guard let data = d.data(forKey: Keys.alerts),
              let value = try? JSONDecoder().decode(AlertPreferences.self, from: data)
        else { return .default }
        return value
    }
    private static func readCommunity(_ d: UserDefaults) -> CommunityPreferences {
        guard let data = d.data(forKey: Keys.community),
              let value = try? JSONDecoder().decode(CommunityPreferences.self, from: data)
        else { return .default }
        return value
    }
    private static func readGlucoseSchedule(_ d: UserDefaults) -> GlucoseSchedule {
        guard let data = d.data(forKey: Keys.glucoseSchedule),
              let value = try? JSONDecoder().decode(GlucoseSchedule.self, from: data)
        else { return .default }
        return value
    }
    private static func readGlucoseGoals(_ d: UserDefaults) -> GlucoseGoals {
        guard let data = d.data(forKey: Keys.glucoseGoals),
              let value = try? JSONDecoder().decode(GlucoseGoals.self, from: data)
        else { return .default }
        return value
    }
    private static func readRingGoals(_ d: UserDefaults) -> RingGoals {
        guard let data = d.data(forKey: Keys.ringGoals),
              let value = try? JSONDecoder().decode(RingGoals.self, from: data)
        else { return .default }
        return value
    }
    private static func readActivityGoals(_ d: UserDefaults) -> ActivityGoals {
        guard let data = d.data(forKey: Keys.activityGoals),
              let value = try? JSONDecoder().decode(ActivityGoals.self, from: data)
        else { return .default }
        return value
    }
    private static func readPeriodTIRTargets(_ d: UserDefaults) -> PeriodTIRTargets {
        guard let data = d.data(forKey: Keys.periodTIRTargets),
              let value = try? JSONDecoder().decode(PeriodTIRTargets.self, from: data)
        else { return .default }
        return value
    }
    private static func readChartEventKinds(_ d: UserDefaults) -> Set<ChartEventKind> {
        guard let data = d.data(forKey: Keys.chartEventKinds),
              let value = try? JSONDecoder().decode(Set<ChartEventKind>.self, from: data)
        else { return ChartEventKind.allShown }
        return value
    }
    private static func readMedicationPlan(_ d: UserDefaults) -> MedicationPlan {
        guard let data = d.data(forKey: Keys.medicationPlan),
              let value = try? JSONDecoder().decode(MedicationPlan.self, from: data)
        else { return .empty }
        return value
    }
    private static func readEmergencyInfo(_ d: UserDefaults) -> EmergencyInfo {
        guard let data = d.data(forKey: Keys.emergencyInfo),
              let value = try? JSONDecoder().decode(EmergencyInfo.self, from: data)
        else { return .default }
        return value
    }
    private static func readCriticalAlarm(_ d: UserDefaults) -> CriticalAlarmPreferences {
        guard let data = d.data(forKey: Keys.criticalAlarm),
              let value = try? JSONDecoder().decode(CriticalAlarmPreferences.self, from: data)
        else { return .default }
        return value
    }

    private static func readAlertSounds(_ d: UserDefaults) -> AlertSoundPreferences {
        guard let data = d.data(forKey: Keys.alertSounds),
              let value = try? JSONDecoder().decode(AlertSoundPreferences.self, from: data)
        else { return .default }
        return value
    }
}

/// One person to call in an emergency.
struct EmergencyContact: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var phone: String = ""
}

/// What the emergency card shows a helper: who to call, where the glucagon is,
/// and anything else they should know. All empty by default.
struct EmergencyInfo: Codable, Equatable, Sendable {
    var contacts: [EmergencyContact] = []
    var glucagonLocation: String = ""
    var notes: String = ""

    static let `default` = EmergencyInfo()

    /// True once the user has filled in anything worth showing.
    var hasContent: Bool {
        !contacts.isEmpty || !glucagonLocation.isEmpty || !notes.isEmpty
    }
}

// NOTE: `CriticalAlarmPreferences` moved to CriticalAlarmPlanner.swift
// (Domain/Alerts) so the widget target — which evaluates alerts from its
// self-fetched readings — can compile it without this file.

/// Opt-in glucose goals: a target Time-in-Range percentage and target A1c, with
/// a streak of days meeting the TIR goal. Off by default and stored under its own
/// preference key, so adding it is a purely additive, migration-safe change.
struct GlucoseGoals: Codable, Equatable, Sendable {
    /// Target time-in-range, as a percentage (e.g. 70 for 70%).
    var targetTIRPercent: Double = 70
    /// Target estimated A1c (%).
    var targetA1c: Double = 7.0
    /// Whether the goals card and streak are shown.
    var enabled: Bool = false

    static let `default` = GlucoseGoals()

    /// The TIR target as a 0…1 fraction, matching `PeriodStatistics.timeInRange`
    /// and the fraction `StreakCalculator` expects.
    var targetTIRFraction: Double { targetTIRPercent / 100 }
}

/// Goals for the two daily rings that aren't the Time-in-Range ring: a movement
/// target (active minutes/day) and a sensor-uptime target (% of the elapsed day
/// with CGM data). Stored under their own key so this is a migration-safe,
/// purely additive change.
struct RingGoals: Codable, Equatable, Sendable {
    /// Daily active-minutes target for the Active ring (default 30, per WHO's
    /// ~150 min/week guidance).
    var activeMinutesGoal: Int = 30
    /// Sensor-uptime target for the Sensor ring, as a percentage of the elapsed
    /// day (default 85; consensus calls ≥ 70 % "reliable").
    var coverageGoalPercent: Double = 85

    static let `default` = RingGoals()

    /// The uptime target as a 0…1 fraction, matching `DailyRings.coverageFraction`.
    var coverageGoalFraction: Double { coverageGoalPercent / 100 }
}

/// Editable daily targets for the Health-hub activity rings and their streaks:
/// steps, active energy (kcal) and exercise minutes. Sensible defaults (10k
/// steps, 500 kcal, 30 min); stored under its own key so this is a purely
/// additive, migration-safe change.
struct ActivityGoals: Codable, Equatable, Sendable {
    var stepGoal: Int = 10_000
    var moveGoalKcal: Int = 500
    var exerciseMinutesGoal: Int = 30

    static let `default` = ActivityGoals()
}

/// Optional per-time-of-day Time-in-Range targets. Some people run tighter by
/// day and looser overnight (to reduce nocturnal-hypo risk), so each `DayPeriod`
/// can carry its own goal. When `enabled` is false, callers fall back to the
/// single global TIR target.
///
/// Tolerant `Codable`: a hand-written `init(from:)` uses `decodeIfPresent` so
/// future fields (or an older payload) never wipe a user's saved targets.
struct PeriodTIRTargets: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var overnightPercent: Double = 70
    var morningPercent: Double = 70
    var afternoonPercent: Double = 70
    var eveningPercent: Double = 70

    static let `default` = PeriodTIRTargets()

    init(enabled: Bool = false,
         overnightPercent: Double = 70,
         morningPercent: Double = 70,
         afternoonPercent: Double = 70,
         eveningPercent: Double = 70) {
        self.enabled = enabled
        self.overnightPercent = overnightPercent
        self.morningPercent = morningPercent
        self.afternoonPercent = afternoonPercent
        self.eveningPercent = eveningPercent
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, overnightPercent, morningPercent, afternoonPercent, eveningPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = PeriodTIRTargets.default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? base.enabled
        overnightPercent = try c.decodeIfPresent(Double.self, forKey: .overnightPercent) ?? base.overnightPercent
        morningPercent = try c.decodeIfPresent(Double.self, forKey: .morningPercent) ?? base.morningPercent
        afternoonPercent = try c.decodeIfPresent(Double.self, forKey: .afternoonPercent) ?? base.afternoonPercent
        eveningPercent = try c.decodeIfPresent(Double.self, forKey: .eveningPercent) ?? base.eveningPercent
    }

    /// The target percentage for a period — the period-specific value when
    /// enabled, otherwise the caller's global target.
    func targetPercent(for period: DayPeriod, global: Double) -> Double {
        guard enabled else { return global }
        switch period {
        case .overnight: return overnightPercent
        case .morning: return morningPercent
        case .afternoon: return afternoonPercent
        case .evening: return eveningPercent
        }
    }

    /// The target as a 0…1 fraction, matching `PeriodStatistics.timeInRange`.
    func targetFraction(for period: DayPeriod, global: Double) -> Double {
        targetPercent(for: period, global: global) / 100
    }
}

/// The connection details for a self-hosted Nightscout site. The URL and token
/// are entered by the user and used only to fetch readings directly from their
/// server; they never leave the device otherwise.
struct NightscoutConfig: Codable, Equatable, Sendable {
    var urlString: String = ""
    var token: String = ""

    static let empty = NightscoutConfig()

    /// The site URL with a scheme guaranteed and any trailing slash removed, or
    /// `nil` when the string can't form a URL.
    var normalizedBaseURL: URL? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// True once there is a usable site URL — the source syncs only then.
    var isConfigured: Bool { normalizedBaseURL != nil }
}

/// One glucose-logging slot the user has chosen — a named time of day they want
/// to check and record their glucose (e.g. "Waking" at 07:00).
struct GlucoseLogSlot: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var label: String
    /// Minutes from midnight, so it serialises cleanly and stays relative to the
    /// user's day.
    var minutesFromMidnight: Int
    var enabled: Bool = true

    var hour: Int { minutesFromMidnight / 60 }
    var minute: Int { minutesFromMidnight % 60 }
}

/// The user's personal glucose-logging routine: the times of day they want to
/// take and record a reading, with optional reminders. Stored separately from
/// `ReminderPreferences` so adding it never disturbs existing reminder settings.
struct GlucoseSchedule: Codable, Equatable, Sendable {
    var remindersEnabled = false
    var slots: [GlucoseLogSlot] = GlucoseSchedule.defaultSlots

    /// Enabled slots in chronological order.
    var activeSlots: [GlucoseLogSlot] {
        slots.filter(\.enabled).sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
    }

    // Stored as their English keys (not localized at construction) so the schedule
    // screen can translate them at display time and follow an in-app language
    // override. See GlucoseScheduleView.localizedLabel.
    static let defaultSlots: [GlucoseLogSlot] = [
        GlucoseLogSlot(label: "Waking", minutesFromMidnight: 7 * 60),
        GlucoseLogSlot(label: "Before lunch", minutesFromMidnight: 12 * 60),
        GlucoseLogSlot(label: "Before dinner", minutesFromMidnight: 18 * 60),
        GlucoseLogSlot(label: "Bedtime", minutesFromMidnight: 22 * 60)
    ]

    static let `default` = GlucoseSchedule()
}

/// Configurable reminder schedule. Times are minutes-from-midnight so they
/// serialise cleanly and stay time-zone-relative to the user's day.
struct ReminderPreferences: Codable, Equatable, Sendable {
    var journalEnabled = false
    var journalTimes: [Int] = [8 * 60, 20 * 60]        // 08:00, 20:00
    var basalEnabled = false
    var basalTime: Int = 22 * 60                        // 22:00
    var mealsEnabled = false
    var mealTimes: [Int] = [8 * 60, 13 * 60, 19 * 60]   // 08:00, 13:00, 19:00
    var hydrationEnabled = false
    var hydrationIntervalHours = 3
    var glucoseCheckEnabled = false
    var glucoseCheckTimes: [Int] = [7 * 60, 12 * 60, 18 * 60, 22 * 60]

    static let `default` = ReminderPreferences()
}
