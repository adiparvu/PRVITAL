import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// How Prvital's notifications sound — chosen per *category*, because a hypo
/// alarm and a hydration reminder should never be forced to share a voice:
///  - critical: urgent lows/highs, the escalation repeats, the predicted-low
///    warning and falling-fast alerts;
///  - important: out-of-range alerts, rising fast, signal loss;
///  - reminders: daily reminders, smart nudges, the weekly summaries.
///
/// Each category picks a delivery mode (sound / vibration only / silent) and,
/// for sound, one of the bundled tones. "Vibration only" works by attaching a
/// bundled clip of silence: the system treats the delivery as sounded — so the
/// user's vibration settings still fire — but there's nothing to hear.

/// A bundled notification tone. `classic` is the stock iOS notification sound;
/// the rest ship with the app as small WAV files.
enum AlertTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, chime, gentle, pulse, alarm

    var id: String { rawValue }

    /// Bundled file name; nil for the system default sound.
    var fileName: String? {
        switch self {
        case .classic: return nil
        case .chime: return "prvital-chime.wav"
        case .gentle: return "prvital-gentle.wav"
        case .pulse: return "prvital-pulse.wav"
        case .alarm: return "prvital-alarm.wav"
        }
    }

    var label: String {
        switch self {
        case .classic: return String(localized: "System default")
        case .chime: return String(localized: "Chime")
        case .gentle: return String(localized: "Gentle")
        case .pulse: return String(localized: "Pulse")
        case .alarm: return String(localized: "Alarm")
        }
    }
}

enum AlertSoundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case sound, vibrateOnly, silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sound: return String(localized: "Sound")
        case .vibrateOnly: return String(localized: "Vibration only")
        case .silent: return String(localized: "Silent")
        }
    }
}

/// One category's delivery choice.
struct AlertSoundSetting: Codable, Equatable, Sendable {
    var mode: AlertSoundMode
    var tone: AlertTone

    /// The bundled 0.5 s silent clip behind "vibration only".
    static let silenceFile = "prvital-silence.wav"

    /// The bundled file this setting resolves to; nil when the delivery should
    /// carry no sound at all, or when it uses the system default (see
    /// `usesSystemDefault`). Pure, so the mapping is unit-testable.
    var resolvedFileName: String? {
        switch mode {
        case .silent: return nil
        case .vibrateOnly: return Self.silenceFile
        case .sound: return tone.fileName
        }
    }

    var usesSystemDefault: Bool { mode == .sound && tone == .classic }

    /// The value shown next to the category row in Settings.
    var summaryLabel: String {
        switch mode {
        case .sound: return tone.label
        case .vibrateOnly, .silent: return mode.label
        }
    }

    #if canImport(UserNotifications)
    /// The sound to attach to a notification. If a bundled file ever went
    /// missing, the system's documented fallback is the default sound — an
    /// alert can get louder by accident, never silent.
    var notificationSound: UNNotificationSound? {
        if usesSystemDefault { return .default }
        guard let file = resolvedFileName else { return nil }
        return UNNotificationSound(named: UNNotificationSoundName(file))
    }
    #endif
}

struct AlertSoundPreferences: Codable, Equatable, Sendable {
    /// Critical ships loud and unmistakable by default; everything else keeps
    /// the familiar system sound until the user says otherwise.
    var critical = AlertSoundSetting(mode: .sound, tone: .alarm)
    var important = AlertSoundSetting(mode: .sound, tone: .classic)
    var reminders = AlertSoundSetting(mode: .sound, tone: .classic)

    static let `default` = AlertSoundPreferences()
}

/// Static access to the persisted preferences for the delivery sites that
/// can't hold a `Preferences` instance (static schedulers, the alert service).
/// The key literal must match `Preferences.Keys.alertSounds`, which keeps the
/// stored JSON up to date via its `didSet`.
enum AlertSoundStore {
    static let key = "pref.alertSounds"

    static func load() -> AlertSoundPreferences {
        // SharedStore's group id (not AppSchema's) so this file also compiles
        // in the widget target, whose alert delivery reads the same choice.
        let defaults = UserDefaults(suiteName: SharedStore.appGroupIdentifier) ?? .standard
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AlertSoundPreferences.self, from: data)
        else { return .default }
        return value
    }
}
