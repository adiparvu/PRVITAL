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
        self.glucoseSchedule = Self.readGlucoseSchedule(self.defaults)
        self.glucoseGoals = Self.readGlucoseGoals(self.defaults)
        self.liveSyncSeconds = (self.defaults.object(forKey: Keys.liveSync) as? Int) ?? 60
        self.sickDayEnabled = self.defaults.bool(forKey: Keys.sickDayEnabled)
        self.sickDayStartedAt = self.defaults.object(forKey: Keys.sickDayStartedAt) as? Date
        self.emergencyInfo = Self.readEmergencyInfo(self.defaults)
        self.criticalAlarm = Self.readCriticalAlarm(self.defaults)
        self.weeklyDigestEnabled = self.defaults.bool(forKey: Keys.weeklyDigest)
        self.nightscoutUploadEnabled = self.defaults.bool(forKey: Keys.nightscoutUpload)
        self.accentThemeRaw = self.defaults.string(forKey: Keys.accentTheme) ?? "default"
        self.journalCardDensityRaw = self.defaults.string(forKey: Keys.journalCardDensity) ?? "standard"
        self.lastSeenWhatsNewVersion = self.defaults.string(forKey: Keys.lastSeenWhatsNew) ?? ""
        self.themeModeRaw = self.defaults.string(forKey: Keys.themeMode) ?? ThemeMode.system.rawValue
        self.useSystemTextSize = (self.defaults.object(forKey: Keys.useSystemTextSize) as? Bool) ?? true
        self.textSizeRaw = self.defaults.string(forKey: Keys.textSize) ?? AppTextSize.large.rawValue
        self.hapticsEnabled = (self.defaults.object(forKey: Keys.hapticsEnabled) as? Bool) ?? true
        self.backgroundKindRaw = self.defaults.string(forKey: Keys.backgroundKind) ?? AppBackgroundKind.standard.rawValue
        self.backgroundGradientRaw = self.defaults.string(forKey: Keys.backgroundGradient) ?? BackgroundGradient.aurora.rawValue
        self.backgroundPhotoData = self.defaults.data(forKey: Keys.backgroundPhoto)
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

    /// How often (seconds) to poll connected CGM sources while the app is open.
    /// 0 disables live polling. Default 60s, which matches a Libre's per-minute
    /// cadence; Dexcom publishes every 5 minutes so extra polls simply no-op.
    var liveSyncSeconds: Int {
        didSet { defaults.set(liveSyncSeconds, forKey: Keys.liveSync) }
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

    /// Monday-morning "your week in review" summary. Off by default.
    var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Keys.weeklyDigest) }
    }

    /// Mirror the user's entries up to their own Nightscout site. Off by default.
    /// A separate key (not a field on `NightscoutConfig`) so enabling it can
    /// never invalidate an already-stored connection config.
    var nightscoutUploadEnabled: Bool {
        didSet { defaults.set(nightscoutUploadEnabled, forKey: Keys.nightscoutUpload) }
    }

    /// The chosen accent theme's raw identifier ("default" = the teal brand).
    var accentThemeRaw: String {
        didSet { defaults.set(accentThemeRaw, forKey: Keys.accentTheme) }
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
    /// The chosen background photo, if any (JPEG/PNG data). Stored in the shared
    /// defaults so it survives relaunches; nil clears it.
    var backgroundPhotoData: Data? {
        didSet {
            if let backgroundPhotoData {
                defaults.set(backgroundPhotoData, forKey: Keys.backgroundPhoto)
            } else {
                defaults.removeObject(forKey: Keys.backgroundPhoto)
            }
        }
    }

    /// Quick-add presets (the +1U … +10U row and 20g … 100g row).
    let insulinPresets: [Double] = [1, 2, 4, 6, 8, 10]
    let carbPresets: [Double] = [20, 40, 60, 80, 100]
    let activityDurations: [Int] = [15, 30, 45, 60, 90, 120]

    // MARK: Persistence

    private enum Keys {
        static let unit = "pref.glucoseUnit"
        static let thresholds = "pref.thresholds"
        static let reminders = "pref.reminders"
        static let nightscout = "pref.nightscout"
        static let bolus = "pref.bolusParameters"
        static let alerts = "pref.alerts"
        static let glucoseSchedule = "pref.glucoseSchedule"
        static let glucoseGoals = "pref.glucoseGoals"
        static let liveSync = "pref.liveSyncSeconds"
        static let sickDayEnabled = "pref.sickDayEnabled"
        static let sickDayStartedAt = "pref.sickDayStartedAt"
        static let emergencyInfo = "pref.emergencyInfo"
        static let criticalAlarm = "pref.criticalAlarm"
        static let weeklyDigest = "pref.weeklyDigestEnabled"
        static let nightscoutUpload = "pref.nightscoutUploadEnabled"
        static let accentTheme = "pref.accentTheme"
        static let journalCardDensity = "pref.journalCardDensity"
        static let lastSeenWhatsNew = "pref.lastSeenWhatsNewVersion"
        static let themeMode = ThemeMode.preferenceKey
        static let useSystemTextSize = "pref.useSystemTextSize"
        static let textSize = AppTextSize.preferenceKey
        static let hapticsEnabled = "pref.hapticsEnabled"
        static let backgroundKind = AppBackgroundKind.preferenceKey
        static let backgroundGradient = BackgroundGradient.preferenceKey
        static let backgroundPhoto = AppBackgroundKind.photoKey
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

/// Repeat-until-acknowledged escalation for urgent-low alerts. Off by default;
/// when on, the urgent-low notification re-fires every `repeatMinutes` until the
/// user acknowledges it or `maxRepeats` is reached.
struct CriticalAlarmPreferences: Codable, Equatable, Sendable {
    var escalationEnabled: Bool = false
    var repeatMinutes: Int = 5
    var maxRepeats: Int = 6

    static let `default` = CriticalAlarmPreferences()
}

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

    static let defaultSlots: [GlucoseLogSlot] = [
        GlucoseLogSlot(label: String(localized: "Waking"), minutesFromMidnight: 7 * 60),
        GlucoseLogSlot(label: String(localized: "Before lunch"), minutesFromMidnight: 12 * 60),
        GlucoseLogSlot(label: String(localized: "Before dinner"), minutesFromMidnight: 18 * 60),
        GlucoseLogSlot(label: String(localized: "Bedtime"), minutesFromMidnight: 22 * 60)
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
