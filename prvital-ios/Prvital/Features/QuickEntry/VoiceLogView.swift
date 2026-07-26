import SwiftUI
import Speech
import AVFoundation
import UIKit

/// Voice logging: press the mic, say "60 de grame, pizza" or "6 unități", watch
/// the entries appear as chips, then confirm with one tap. Speech never saves
/// anything by itself — for medical data the user always sees exactly what was
/// understood before it lands in the journal.
///
/// Recognition runs on-device whenever the recogniser supports it, matching the
/// app's privacy-first stance; the transcription itself never leaves the phone.
struct VoiceLogSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var controller = VoiceLogController()

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var parsed: VoiceEntryParser.Result { VoiceEntryParser.parse(controller.transcript) }

    /// The spoken glucose as mg/dL, kept only when it's a physiologically
    /// plausible reading — a misheard "3200" should never become an entry.
    private var glucoseMgdL: Double? {
        guard let spoken = parsed.spokenGlucose else { return nil }
        let mgdL = VoiceEntryParser.glucoseMgdL(fromSpoken: spoken, preferred: unit)
        return (20...600).contains(mgdL) ? mgdL : nil
    }
    private var carbsGrams: Double? {
        guard let grams = parsed.carbsGrams, (0.5...400).contains(grams) else { return nil }
        return grams
    }
    private var insulinUnits: Double? {
        guard let units = parsed.insulinUnits, (0.25...100).contains(units) else { return nil }
        return units
    }
    private var hasEntries: Bool {
        carbsGrams != nil || insulinUnits != nil || glucoseMgdL != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch controller.phase {
                    case .denied:
                        deniedCard
                    case .unavailable:
                        unavailableCard
                    case .idle, .listening:
                        micButton
                            .padding(.top, 12)
                        statusArea
                        if hasEntries {
                            recognizedChips
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Voice logging")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasEntries {
                    saveButton
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: hasEntries)
        }
        .onDisappear { controller.finish() }
    }

    // MARK: Mic

    private var isListening: Bool { controller.phase == .listening }

    private var micButton: some View {
        Button {
            Haptics.play(.selection)
            Task { await controller.toggle() }
        } label: {
            ZStack {
                // A soft breathing halo while listening, so the state is obvious
                // from across the room.
                Circle()
                    .fill(Theme.accent.opacity(isListening ? 0.20 : 0.0))
                    .frame(width: 132, height: 132)
                    .scaleEffect(isListening ? 1.0 : 0.7)
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isListening)
                    .contentTransition(.symbolEffect(.replace))
            }
            // Repeat only while listening; otherwise a plain settle, or the
            // "off" transition would pulse forever too.
            .animation(
                isListening
                    ? .smooth(duration: 1.1).repeatForever(autoreverses: true)
                    : .smooth(duration: 0.3),
                value: isListening
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Stop listening" : "Start listening")
    }

    private var statusArea: some View {
        VStack(spacing: 10) {
            if isListening {
                Text("Listening…")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            } else {
                Text("Tap the microphone, then say what you want to log.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            if controller.transcript.isEmpty {
                Text("Try: “60 grams, pizza”, “6 units”, “glucose 120”.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(controller.transcript)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .glassCard(cornerRadius: 16, padding: 14)
                    .animation(.default, value: controller.transcript)
            }
        }
    }

    // MARK: Recognized entries

    private var recognizedChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recognized")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            if let grams = carbsGrams {
                entryChip(
                    symbol: "fork.knife", tint: Theme.zoneHigh,
                    value: "\(grams.formatted()) g",
                    detail: parsed.foodDescription
                )
            }
            if let units = insulinUnits {
                entryChip(
                    symbol: "syringe.fill", tint: Theme.accent,
                    value: "\(units.formatted()) U",
                    detail: nil
                )
            }
            if let mgdL = glucoseMgdL {
                entryChip(
                    symbol: "drop.fill", tint: Theme.zoneCritical,
                    value: "\(unit.fromMgdL(mgdL).formatted(.number.precision(.fractionLength(unit.fractionDigits)))) \(unit.rawValue)",
                    detail: nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryChip(symbol: String, tint: Color, value: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .circle)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.zoneInRange)
        }
        .glassCard(cornerRadius: 16, padding: 12)
        .accessibilityElement(children: .combine)
    }

    private var saveButton: some View {
        Button {
            saveAll()
        } label: {
            Label("Save", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    private func saveAll() {
        controller.finish()
        if let mgdL = glucoseMgdL {
            _ = env.entryStore.addGlucose(mgdL: mgdL)
        }
        // When a meal was spoken too, only the meal announces on the Island —
        // two confirmations for one sentence would fight each other.
        if let units = insulinUnits {
            _ = env.entryStore.addInsulin(units: units, announces: carbsGrams == nil)
        }
        if let grams = carbsGrams {
            _ = env.entryStore.addCarbs(
                grams: grams,
                mealType: MealTimeClassifier.mealType(for: Date()),
                foodDescription: parsed.foodDescription
            )
        }
        Haptics.play(.success)
        dismiss()
    }

    // MARK: Permission / availability states

    private var deniedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Allow microphone and speech recognition in Settings to log by voice.")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .glassCard(cornerRadius: 18, padding: 20)
        .padding(.top, 24)
    }

    private var unavailableCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Speech recognition isn't available on this device.")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .glassCard(cornerRadius: 18, padding: 20)
        .padding(.top, 24)
    }
}

// MARK: - Controller

/// Owns the audio engine + recognition task. Kept apart from the view so the
/// teardown story is explicit: `finish()` always runs on dismiss, the audio
/// session never outlives the sheet.
@MainActor
@Observable
final class VoiceLogController {
    enum Phase: Equatable { case idle, listening, denied, unavailable }

    var phase: Phase = .idle
    var transcript = ""

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// The audio tap runs on the audio thread; `append(_:)` is documented safe
    /// to call from there. The box only exists to say so to the compiler.
    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    func toggle() async {
        if phase == .listening {
            stopListening()
        } else {
            await start()
        }
    }

    func start() async {
        guard phase != .listening else { return }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            phase = .denied
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .denied
            return
        }

        // Recognise in the user's language, falling back to English rather
        // than failing outright.
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            phase = .unavailable
            return
        }

        transcript = ""
        self.audioEngine = engine
        self.recognizer = recognizer
        self.request = request
        phase = .listening

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = (result?.isFinal ?? false) || error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                }
                if finished, self.phase == .listening {
                    self.stopListening()
                }
            }
        }
    }

    /// Stops capturing but lets the recogniser deliver its final (usually
    /// better) transcription, which still lands in `transcript`.
    func stopListening() {
        guard phase == .listening else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        audioEngine = nil
        request = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Full teardown on dismiss — nothing may keep recording after the sheet.
    func finish() {
        stopListening()
        task?.cancel()
        task = nil
        recognizer = nil
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return VoiceLogSheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}
