import SwiftUI
import SwiftData

// MARK: - Pure logic

/// Constants and formatting for the "rule of 15/15": treat a low with 15 g of
/// fast-acting carbs, wait 15 minutes, recheck; repeat until back in range. This
/// is general education, not a dosing tool — it never computes an insulin dose.
enum RuleOf15 {
    /// Grams of fast-acting carbohydrate per treatment round.
    static let fastCarbGrams = 15
    /// Minutes to wait before rechecking.
    static let waitMinutes = 15
    /// The wait as seconds, for the countdown.
    static let waitSeconds = waitMinutes * 60

    /// "M:SS" for a remaining-seconds value. Rounds up so the clock reads the full
    /// 15:00 at the start and only reaches 0:00 exactly at the end.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Pure, testable state for the guided Rule-of-15 flow. It owns the phase and the
/// round counter and makes the recheck decision; the SwiftUI view drives the timer
/// and reads the latest glucose. No SwiftUI or timer types leak in here.
struct RuleOf15State: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Show the 15 g fast-carb options and the "I've taken 15 g" button.
        case treat
        /// The 15-minute countdown is running.
        case waiting
        /// Back at or above the low threshold.
        case resolved
    }

    private(set) var phase: Phase = .treat
    /// How many times the user has confirmed taking 15 g of fast carbs.
    private(set) var round = 0

    /// True on a `treat` step that was reached by looping back from a still-low
    /// recheck (so the view can show "Still low — treat again").
    var isRepeatTreat: Bool { phase == .treat && round >= 1 }

    /// The user confirms they've taken 15 g — start (or restart) the wait.
    mutating func takeCarbs() {
        round += 1
        phase = .waiting
    }

    /// Evaluate a rechecked value against the low threshold (both in mg/dL). A
    /// value at or above the target lower bound resolves the flow; a still-low
    /// value loops back to another treat step.
    mutating func recheck(mgdL: Double, targetLowerMgdL: Double) {
        phase = mgdL >= targetLowerMgdL ? .resolved : .treat
    }
}

// MARK: - Sheet

/// A guided low-glucose treatment flow that walks the user through the rule of
/// 15/15. Educational guidance only — it shows widely-published fast-carb examples
/// and a timer, reads the user's own readings for the recheck, and never suggests
/// an insulin dose.
struct RuleOf15Sheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query private var readings: [GlucoseReading]

    init() {
        // Only the latest reading and a little recent context matter here, so a
        // tight window keeps the sheet instant even after a full-history import.
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            ?? Date().addingTimeInterval(-2 * 86_400)
        _readings = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                          sort: \.timestamp, order: .reverse)
    }

    @State private var state = RuleOf15State()
    /// When the current wait started, so an old reading can't resolve the flow —
    /// only a reading logged after this counts for the recheck.
    @State private var roundStartedAt = Date()
    /// The moment the countdown ends.
    @State private var deadline: Date?
    /// True when a recheck found no reading logged since this round started.
    @State private var awaitingReading = false
    @State private var showFingerstick = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    /// The newest active reading, if any.
    private var latestReading: GlucoseReading? {
        readings.filter(\.isActive).max { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    switch state.phase {
                    case .treat: treatStep
                    case .waiting: if let deadline { waitingStep(deadline: deadline) }
                    case .resolved: resolvedStep
                    }
                    disclaimer
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Treat a low")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(state.phase == .resolved ? "Done" : "Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showFingerstick) { GlucoseEntrySheet() }
        }
    }

    // MARK: Step 1 — treat

    private var treatStep: some View {
        VStack(spacing: 18) {
            header(
                icon: "cross.case.fill",
                tint: Theme.zoneWarning,
                title: state.isRepeatTreat ? "Still low — treat again" : "Treat the low",
                subtitle: state.isRepeatTreat
                    ? "Your glucose is still below \(GlucoseFormatting.labeled(mgdL: thresholds.targetLower, unit: unit)). Take another \(RuleOf15.fastCarbGrams) g of fast carbs."
                    : "If you can safely swallow, take \(RuleOf15.fastCarbGrams) g of fast-acting carbs now."
            )

            if state.round >= 1 {
                Text(state.round == 1
                    ? String(localized: "You've treated \(state.round) time so far.")
                    : String(localized: "You've treated \(state.round) times so far."))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard("\(RuleOf15.fastCarbGrams) g fast-carb options", systemImage: "bolt.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    carbOption(String(localized: "3–4 glucose tablets"))
                    Divider().overlay(Theme.hairline)
                    carbOption(String(localized: "150 ml (½ cup) juice or regular, non-diet soda"))
                    Divider().overlay(Theme.hairline)
                    carbOption(String(localized: "1 tablespoon of honey or sugar"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Haptics.play(.medium)
                startWait()
            } label: {
                Label("I've taken \(RuleOf15.fastCarbGrams) g", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .accessibilityHint("Starts a \(RuleOf15.waitMinutes) minute wait before rechecking")
        }
    }

    private func carbOption(_ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.zoneInRange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step 2 — wait & recheck

    @ViewBuilder
    private func waitingStep(deadline: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let finished = remaining <= 0.5
            let progress = 1 - min(max(remaining / Double(RuleOf15.waitSeconds), 0), 1)

            VStack(spacing: 22) {
                header(
                    icon: "hourglass",
                    tint: Theme.accent,
                    title: "Wait \(RuleOf15.waitMinutes) minutes",
                    subtitle: "Give the carbs time to work. Try not to treat again yet — over-treating can cause a rebound high."
                )

                ZStack {
                    Circle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke((finished ? Theme.zoneInRange : Theme.accent).gradient,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: progress)
                    VStack(spacing: 2) {
                        Text(RuleOf15.clock(remaining))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text(finished ? "Time to recheck" : "until recheck")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 184, height: 184)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(finished ? "Time to recheck your glucose" : "\(RuleOf15.clock(remaining)) until recheck")

                if awaitingReading {
                    noFreshReadingHint
                }

                Button {
                    Haptics.play(.selection)
                    performRecheck()
                } label: {
                    Label("Recheck glucose", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(finished ? Theme.accent : Theme.textSecondary)
                .accessibilityHint("Reads your latest glucose to see if you're back in range")
            }
        }
    }

    /// Shown when Recheck is tapped but no reading has been logged since this round
    /// started — points the user at the existing glucose editor.
    private var noFreshReadingHint: some View {
        VStack(spacing: 10) {
            Text("No new reading yet. Log a fingerstick, then recheck.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.play(.light)
                showFingerstick = true
            } label: {
                Label("Log a fingerstick", systemImage: "drop.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18, padding: 14)
        .transition(.opacity)
    }

    // MARK: Step 3 — resolved

    private var resolvedStep: some View {
        VStack(spacing: 18) {
            header(
                icon: "checkmark.seal.fill",
                tint: Theme.zoneInRange,
                title: "Back in range",
                subtitle: "Your glucose is back at or above \(GlucoseFormatting.labeled(mgdL: thresholds.targetLower, unit: unit)). Nicely done."
            )

            if state.round > 1 {
                Text("It took \(state.round) rounds of \(RuleOf15.fastCarbGrams) g to recover.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard("Snack tip", systemImage: "fork.knife") {
                Text("If your next meal is more than an hour away, have a small snack with some longer-lasting carbs and a little protein to stop the low from returning.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Haptics.play(.success)
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.zoneInRange)
        }
    }

    // MARK: Shared

    private func header(icon: String, tint: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.14), in: .circle)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("This is general guidance — follow your care team's plan. If you can't treat the low yourself, your glucose keeps falling, or symptoms are severe (confusion, seizures, passing out), it's an emergency: use glucagon if you have it and seek urgent help.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func startWait() {
        roundStartedAt = Date()
        awaitingReading = false
        deadline = Date().addingTimeInterval(Double(RuleOf15.waitSeconds))
        withAnimation(.smooth) { state.takeCarbs() }
    }

    /// Uses the user's own latest reading for the recheck. Only a reading logged
    /// after this round started counts, so the original low reading can't resolve
    /// the flow; with none, we prompt for a fingerstick instead of guessing.
    private func performRecheck() {
        guard let latest = latestReading, latest.timestamp >= roundStartedAt else {
            withAnimation(.smooth) { awaitingReading = true }
            return
        }
        awaitingReading = false
        let wasResolved = state.phase == .resolved
        withAnimation(.smooth) {
            state.recheck(mgdL: latest.valueMgdL, targetLowerMgdL: thresholds.targetLower)
        }
        if state.phase == .treat {
            Haptics.play(.warning)      // still low — another round
        } else if !wasResolved {
            Haptics.play(.success)
        }
    }
}

#Preview("Treat") {
    let env = AppEnvironment.preview()
    return RuleOf15Sheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}
