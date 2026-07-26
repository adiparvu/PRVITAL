import SwiftUI
import AVFoundation

/// Settings for how each notification category sounds: pick a delivery mode
/// (sound / vibration only / silent) and, for sound, audition and choose a
/// tone. Critical, important and reminders are configured independently — a
/// hypo alarm and a hydration nudge should never share a voice.

/// The three sound categories, each mapping to its slice of
/// `AlertSoundPreferences` and describing what it covers.
enum AlertSoundCategory: String, CaseIterable, Identifiable {
    case critical, important, reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .critical: return String(localized: "Critical alerts")
        case .important: return String(localized: "Important alerts")
        case .reminders: return String(localized: "Reminders")
        }
    }

    var explanation: String {
        switch self {
        case .critical:
            return String(localized: "Urgent lows and highs, the escalation repeats, the predicted-low warning and falling-fast alerts.")
        case .important:
            return String(localized: "Out-of-range alerts, rising fast and signal loss.")
        case .reminders:
            return String(localized: "Daily reminders, smart nudges and the weekly summaries.")
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .important: return "bell.fill"
        case .reminders: return "clock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .critical: return Theme.zoneCritical
        case .important: return Theme.zoneHigh
        case .reminders: return Theme.accent
        }
    }

    var keyPath: WritableKeyPath<AlertSoundPreferences, AlertSoundSetting> {
        switch self {
        case .critical: return \.critical
        case .important: return \.important
        case .reminders: return \.reminders
        }
    }
}

/// The per-category picker screen: delivery mode on top, the tone list (with
/// tap-to-audition) when sound is on, and the honest fine print about the
/// Ring/Silent switch at the bottom.
struct AlertSoundPickerView: View {
    let category: AlertSoundCategory

    @Environment(AppEnvironment.self) private var env
    @State private var preview = AlertTonePreviewPlayer()

    private var setting: AlertSoundSetting {
        env.preferences.alertSounds[keyPath: category.keyPath]
    }

    private func update(_ transform: (inout AlertSoundSetting) -> Void) {
        var sounds = env.preferences.alertSounds
        transform(&sounds[keyPath: category.keyPath])
        env.preferences.alertSounds = sounds
    }

    var body: some View {
        Form {
            Section {
                Picker("Delivery", selection: Binding(
                    get: { setting.mode },
                    set: { mode in
                        Haptics.play(.selection)
                        update { $0.mode = mode }
                    }
                )) {
                    ForEach(AlertSoundMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Delivery")
            } footer: {
                Text(category.explanation)
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            if setting.mode == .sound {
                Section {
                    ForEach(AlertTone.allCases) { tone in
                        Button {
                            Haptics.play(.selection)
                            update { $0.tone = tone }
                            preview.play(tone)
                        } label: {
                            HStack {
                                Text(tone.label)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if tone != .classic {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                if setting.tone == tone {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Tap a sound to hear it.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }

            Section {
            } footer: {
                Text("Urgent alerts are Time-Sensitive: they break through Focus and scheduled summaries. When the Ring/Silent switch is on silent, iOS mutes every app's notification sounds — vibration follows your system settings, and the urgent-low escalation keeps repeating until acknowledged. Playing sound over the mute switch requires Apple's per-app Critical Alerts permission, which no app can grant itself.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .animation(.easeInOut(duration: 0.25), value: setting.mode)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { preview.stop() }
    }
}

/// Auditions a bundled tone. Uses the `.playback` audio session category so
/// the preview is audible regardless of the ring switch — the user is
/// deliberately listening to a sound they just tapped.
@MainActor
@Observable
final class AlertTonePreviewPlayer {
    @ObservationIgnored private var player: AVAudioPlayer?

    func play(_ tone: AlertTone) {
        guard let fileName = tone.fileName else { return }   // system default: nothing bundled to play
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true, options: [])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AlertSoundPickerView(category: .critical) }
        .environment(env)
        .modelContainer(env.modelContainer)
}
