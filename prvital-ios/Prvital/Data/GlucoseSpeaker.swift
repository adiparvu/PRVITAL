import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Speaks the current glucose aloud on demand — a hands-free "read it to me"
/// (in the spirit of Sugarmate), useful while driving or cooking and for anyone
/// who'd rather hear it than read it. The phrase matches the Siri intent so the
/// app sounds consistent everywhere.
@MainActor
final class GlucoseSpeaker {
    static let shared = GlucoseSpeaker()
    private init() {}

    #if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    #endif

    /// The sentence spoken for a snapshot. Pure and localized, so it can be unit
    /// tested and reused. Mirrors `CurrentGlucoseIntent`.
    nonisolated static func sentence(for snapshot: GlucoseSnapshot) -> String {
        let value = "\(snapshot.valueText) \(snapshot.unitText)"
        if snapshot.updatedAt == .distantPast {
            return String(localized: "There's no glucose reading yet.")
        }
        if snapshot.isStale {
            return String(localized: "Your last glucose was \(value), \(snapshot.zoneLabel).")
        }
        return String(localized: "Your glucose is \(value), \(snapshot.trendLabel), \(snapshot.zoneLabel).")
    }

    /// Speaks the snapshot aloud, ducking other audio. Safe to call repeatedly —
    /// a new request interrupts the previous utterance.
    func speak(_ snapshot: GlucoseSnapshot) {
        #if canImport(AVFoundation) && os(iOS)
        let text = Self.sentence(for: snapshot)

        // Play over the silent switch and duck (not stop) any music/podcast.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true, options: [])

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        #endif
    }
}
