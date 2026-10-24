import SwiftUI
import Foundation
import WatchKit

/// Root of the watch experience: a vertically-paged glance stack.
///
///   1. **Now** — the current glucose value, trend, zone and freshness.
///   2. **Glucose** — dial in and log a reading with the Digital Crown.
///   3. **Treat a low** — one confirmed tap logs 15 g of fast carbs.
///   4. **Insulin** — one-tap quick doses, confirmed before they are sent.
///   5. **Carbs** — one-tap quick carb amounts, confirmed before they are sent.
///   6. **Emergency** — static "I have diabetes" bystander guidance.
///
/// Everything renders from `model.snapshot`; quick entries are handed to the
/// phone through `WatchSessionManager`, which logs them via the normal audited
/// entry path. Reading `model.snapshot` inside `body` is enough for the
/// `@Observable` model to keep every page live.
struct WatchRootView: View {
    let model: WatchModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            WatchNowPage(snapshot: model.snapshot)

            WatchGlucosePage(snapshot: model.snapshot)

            WatchTreatLowPage()

            WatchQuickEntryPage(
                title: String(localized: "Insulin"),
                systemImage: "syringe",
                kind: "insulin",
                unit: "U",
                values: [1, 2, 4, 6],
                tint: Theme.accent
            )

            WatchQuickEntryPage(
                title: String(localized: "Carbs"),
                systemImage: "fork.knife",
                kind: "carbs",
                unit: "g",
                values: [20, 40, 60],
                tint: Theme.zoneHigh
            )

            WatchEmergencyPage()
        }
        .tabViewStyle(.verticalPage)
        .background(Theme.background.ignoresSafeArea())
        // The watch can't fetch glucose itself, so whenever it comes to the
        // front with an old reading it asks the phone for a fresher one (only
        // when the phone is in reach — otherwise the stale state is the truth).
        .task { askForFresherReading() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { askForFresherReading() }
        }
    }

    private func askForFresherReading() {
        guard model.snapshot.isStale(at: Date()) else { return }
        WatchSessionManager.shared.requestFreshSnapshot()
    }
}

// MARK: - Page 1 · Current glucose

/// The primary glance: a zone-coloured gauge ring around the current value,
/// with trend, zone label, source and time since the last update. When the
/// reading is stale the whole page is dimmed and a clock badge appears.
private struct WatchNowPage: View {
    let snapshot: GlucoseSnapshot

    private var zoneColor: Color { Color(hex: snapshot.zoneColorHex) }

    /// Where the current value sits on a fixed 40–300 mg/dL display sweep,
    /// clamped to the ring. Drives the trimmed arc for a gauge feel.
    private var gaugeFraction: Double {
        let lower = 40.0
        let upper = 300.0
        return min(max((snapshot.mgdL - lower) / (upper - lower), 0), 1)
    }

    var body: some View {
        // Staleness is judged at render time, and the view re-renders every 30 s:
        // the flag the phone published is frozen at publish time, so a reading
        // that ages while the phone is away must be dimmed by the clock, here.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(stale: snapshot.isStale(at: context.date), now: context.date)
        }
    }

    private func content(stale: Bool, now: Date) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(zoneColor.opacity(0.22), style: StrokeStyle(lineWidth: 9))

                Circle()
                    .trim(from: 0, to: max(gaugeFraction, 0.001))
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: snapshot.trendSymbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(zoneColor)

                    Text(snapshot.valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(snapshot.unitText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 122, height: 122)

            Text(snapshot.zoneLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(zoneColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(zoneColor.opacity(0.18), in: Capsule())

            if snapshot.iobText != nil || snapshot.cobText != nil {
                HStack(spacing: 10) {
                    if let iob = snapshot.iobText {
                        Label(iob, systemImage: "syringe.fill")
                            .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    if let cob = snapshot.cobText {
                        Label(cob, systemImage: "fork.knife")
                            .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }

            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(zoneColor)
                        .frame(width: 5, height: 5)
                    Text(snapshot.sourceName)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if stale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.zoneWarning)
                    }
                }
                Text(WatchSnapshotFormat.updated(snapshot.updatedAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(stale ? 0.55 : 1)
        // Entries the phone hasn't confirmed yet — never let "I logged it"
        // quietly mean "I queued it".
        .overlay(alignment: .top) {
            let waiting = WatchOutbox.shared.waitingCount
            if waiting > 0 {
                Label("\(waiting) waiting for iPhone", systemImage: "iphone.slash")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.zoneWarning.opacity(0.85), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchSnapshotFormat.valueSummary(snapshot, stale: stale))
    }
}

// MARK: - Pages 2 & 3 · Quick entry

/// A reusable quick-entry glance shared by the insulin and carb pages. Each
/// amount is a large tap target; tapping it asks for confirmation first (a
/// safeguard for logging medication from the wrist) and, once confirmed, sends
/// the entry to the phone and shows a brief acknowledgement.
private struct WatchQuickEntryPage: View {
    let title: String
    let systemImage: String
    /// "insulin" or "carbs" — matches `WatchSessionManager.sendQuickEntry`.
    let kind: String
    /// Unit suffix shown on each button ("U" or "g").
    let unit: String
    let values: [Double]
    let tint: Color

    @State private var pending: Double?
    @State private var confirmation: WatchLogConfirmation?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        pending = value
                    } label: {
                        VStack(spacing: 1) {
                            Text(WatchSnapshotFormat.amount(value))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            Text(unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(WatchSnapshotFormat.amount(value)) \(WatchSnapshotFormat.unitName(unit))")
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let confirmation {
                WatchSendStatus(entryID: confirmation.entryID, amountText: confirmation.amountText)
            }
        }
        .animation(.spring(duration: 0.3), value: confirmation)
        .confirmationDialog(
            "Log \(WatchSnapshotFormat.amount(pending ?? 0)) \(unit)?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { value in
            Button("Log \(WatchSnapshotFormat.amount(value)) \(unit)") { commit(value) }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .task(id: confirmation?.id) {
            guard let current = confirmation else { return }
            try? await Task.sleep(for: .seconds(2))
            // Still unconfirmed by the phone → leave that on screen a while longer.
            if WatchOutbox.shared.state(of: current.entryID) != .logged {
                try? await Task.sleep(for: .seconds(3))
            }
            confirmation = nil
        }
    }

    private func commit(_ value: Double) {
        let id = WatchSessionManager.shared.sendQuickEntry(kind: kind, amount: value)
        playSendHaptic(for: id)
        pending = nil
        confirmation = WatchLogConfirmation(
            entryID: id, amountText: "\(WatchSnapshotFormat.amount(value)) \(unit)")
    }
}

/// A single "just logged" acknowledgement. The `id` makes repeated identical
/// amounts still re-trigger the auto-dismiss timer.
private struct WatchLogConfirmation: Equatable {
    let id = UUID()
    /// The outbox entry this acknowledgement follows.
    let entryID: UUID
    /// "4 U", "45 g", "112 mg/dL" — already formatted.
    let amountText: String
}

/// A click for an entry on its way, a distinct "retry" tap for one that had to
/// be queued because the iPhone is out of reach.
@MainActor
private func playSendHaptic(for id: UUID) {
    let queued = WatchOutbox.shared.state(of: id) == .queued
    WKInterfaceDevice.current().play(queued ? .retry : .click)
}

/// The honest state of one sent entry, straight from the outbox: still sending,
/// queued for an unreachable iPhone, or confirmed logged. The success haptic
/// plays the moment the phone confirms — not when the button was tapped.
private struct WatchSendStatus: View {
    let entryID: UUID
    let amountText: String

    var body: some View {
        let state = WatchOutbox.shared.state(of: entryID) ?? .logged
        label(for: state)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint(for: state).opacity(0.9), in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: state) { _, new in
                switch new {
                case .logged: WKInterfaceDevice.current().play(.success)
                case .queued: WKInterfaceDevice.current().play(.retry)
                case .sending: break
                }
            }
    }

    @ViewBuilder
    private func label(for state: WatchOutbox.State) -> some View {
        switch state {
        case .logged:
            Label("Logged \(amountText)", systemImage: "checkmark.circle.fill")
        case .sending:
            Label("Sending \(amountText)…", systemImage: "arrow.up.circle.fill")
        case .queued:
            Label("Queued — your iPhone isn't reachable", systemImage: "iphone.slash")
        }
    }

    private func tint(for state: WatchOutbox.State) -> Color {
        switch state {
        case .logged: return Theme.zoneInRange
        case .sending: return Theme.accent
        case .queued: return Theme.zoneWarning
        }
    }
}

// MARK: - Glucose entry

/// Log a glucose reading from the wrist with the Digital Crown. The value is
/// shown in the same unit as the snapshot (mg/dL or mmol/L) and converted to
/// mg/dL before it's sent to the phone, which logs it through the normal path.
private struct WatchGlucosePage: View {
    let snapshot: GlucoseSnapshot

    /// The value the user is dialling, in the *display* unit.
    @State private var value: Double
    @State private var confirmation: WatchLogConfirmation?
    /// The "Log 112 mg/dL?" question — a glucose value is never written on one tap.
    @State private var pending = false

    /// mg/dL per 1 mmol/L, inlined so the watch needs no domain layer.
    private static let mmolFactor = 18.0182

    private var isMmol: Bool { snapshot.usesMmol }
    private var step: Double { isMmol ? 0.1 : 1 }
    private var range: ClosedRange<Double> { isMmol ? GlucoseSnapshot.entryDialMmol : GlucoseSnapshot.entryDialMgdL }
    private var valueText: String {
        isMmol ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    init(snapshot: GlucoseSnapshot) {
        self.snapshot = snapshot
        // Opens on the current reading (or a neutral value when it is stale), so
        // the number being logged is never an arbitrary leftover.
        _value = State(initialValue: snapshot.entryDialSeed(at: Date()))
    }

    var body: some View {
        VStack(spacing: 6) {
            Label("Glucose", systemImage: "drop.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(valueText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: value))
                Text(snapshot.unitText)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .focusable()
            .digitalCrownRotation(
                $value,
                from: range.lowerBound,
                through: range.upperBound,
                by: step,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

            Spacer(minLength: 0)

            Button {
                pending = true
            } label: {
                Text("Log")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let confirmation {
                WatchSendStatus(entryID: confirmation.entryID, amountText: confirmation.amountText)
            }
        }
        .animation(.spring(duration: 0.3), value: confirmation)
        .confirmationDialog(
            "Log \(valueText) \(snapshot.unitText)?",
            isPresented: $pending,
            titleVisibility: .visible
        ) {
            Button("Log \(valueText) \(snapshot.unitText)") { commit() }
            Button("Cancel", role: .cancel) { pending = false }
        }
        .task(id: confirmation?.id) {
            guard let current = confirmation else { return }
            try? await Task.sleep(for: .seconds(2))
            // Still unconfirmed by the phone → leave that on screen a while longer.
            if WatchOutbox.shared.state(of: current.entryID) != .logged {
                try? await Task.sleep(for: .seconds(3))
            }
            confirmation = nil
        }
    }

    private func commit() {
        pending = false
        let mgdL = isMmol ? value * Self.mmolFactor : value
        let id = WatchSessionManager.shared.sendQuickEntry(kind: "glucose", amount: mgdL)
        playSendHaptic(for: id)
        confirmation = WatchLogConfirmation(entryID: id, amountText: "\(valueText) \(snapshot.unitText)")
    }
}

// MARK: - Treat a low (rule of 15)

/// One prominent action for the moment that matters most: treating a low. Logs
/// 15 g of fast-acting carbs (the "rule of 15") in a single confirmed tap.
private struct WatchTreatLowPage: View {
    private let grams: Double = 15
    /// The rule-of-15 recheck deadline, watch-local. `@AppStorage` so the
    /// countdown survives the page being torn down (wrist drop, app switch);
    /// 0 means no wait is running. The phone runs its own richer timer — this
    /// one exists so treating a low FROM THE WATCH gives you the countdown on
    /// the same wrist, without a round-trip.
    @AppStorage("watch.ruleOf15.deadline") private var deadlineEpoch: Double = 0
    @State private var pending = false
    @State private var done = false
    /// The entry the last "Log 15 g" sent, so its delivery state can be shown.
    @State private var sentID: UUID?

    private var deadline: Date? {
        deadlineEpoch > 0 ? Date(timeIntervalSince1970: deadlineEpoch) : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            Label("Treat a low", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let deadline {
                // The wait, live on the wrist. TimelineView ticks the clock;
                // when it runs out the page flips to "recheck now".
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = deadline.timeIntervalSince(context.date)
                    VStack(spacing: 4) {
                        if remaining > 0 {
                            Text(verbatim: clock(remaining))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.zoneWarning)
                            Text("then recheck")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        } else {
                            Text("Recheck now")
                                .font(.headline)
                                .foregroundStyle(Theme.zoneWarning)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
                Button("Stop timer") { deadlineEpoch = 0 }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button {
                    pending = true
                } label: {
                    VStack(spacing: 2) {
                        Text("15 g")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("fast carbs")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(Theme.zoneCritical)
                    .background(Theme.zoneCritical.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Recheck in 15 min.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if done, let sentID {
                WatchSendStatus(entryID: sentID, amountText: "15 g")
            }
        }
        .animation(.spring(duration: 0.3), value: done)
        .confirmationDialog(
            "Log 15 g fast carbs?",
            isPresented: $pending,
            titleVisibility: .visible
        ) {
            Button("Log 15 g") { commit() }
            Button("Cancel", role: .cancel) { pending = false }
        }
        .task(id: done) {
            guard done else { return }
            try? await Task.sleep(for: .seconds(2))
            done = false
        }
    }

    private func commit() {
        sentID = WatchSessionManager.shared.sendQuickEntry(kind: "carbs", amount: grams)
        pending = false
        done = true
        // Start the wrist-side wait alongside the log; haptic marks the start.
        deadlineEpoch = Date().addingTimeInterval(15 * 60).timeIntervalSince1970
        WKInterfaceDevice.current().play(.start)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Emergency card (static)

/// A compact, always-available emergency page a bystander can read off the
/// wrist: "I have diabetes" plus the three standard helper steps.
///
/// Deliberately static. The watch target has no `Preferences` — it renders only
/// from the `GlucoseSnapshot` the phone pushes over WatchConnectivity, and that
/// snapshot carries no emergency contacts or glucagon location (the iPhone's
/// App Group container is not shared across devices). Syncing the personal
/// details here would need new snapshot fields and phone-side plumbing; until
/// then the page points helpers at the full card on the phone.
private struct WatchEmergencyPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Emergency", systemImage: "staroflife.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.zoneCritical)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("I have diabetes")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Confused, shaky or unconscious? This may be severe LOW blood sugar.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                emergencyStep(1, "If I can swallow: give sugar — juice, regular soda or glucose tablets.")
                emergencyStep(2, "If I can't swallow or am unconscious: do NOT give food or drink. Call 112 / 911.")
                emergencyStep(3, "Stay with me until help arrives.")

                Text("Full card — glucagon spot & contacts — is on my phone: Prvital → Settings → Emergency card.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private func emergencyStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Theme.zoneCritical, in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting helpers

/// Small formatting helpers shared by the watch pages. Kept in one place so the
/// glance and quick-entry pages phrase values and times identically.
private enum WatchSnapshotFormat {
    /// Whole numbers render without a decimal; fractions keep one place.
    static func amount(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Spoken form of a unit suffix for VoiceOver.
    static func unitName(_ unit: String) -> String {
        switch unit {
        case "U": return "units"
        case "g": return "grams"
        default: return unit
        }
    }

    /// "Updated 3 min ago", or a friendly fallback when there is no reading yet.
    static func updated(_ date: Date, now: Date = Date()) -> String {
        guard date > .distantPast else { return String(localized: "No recent data") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return String(localized: "Updated \(formatter.localizedString(for: date, relativeTo: now))")
    }

    static func valueSummary(_ snapshot: GlucoseSnapshot, stale: Bool) -> String {
        var summary = "\(snapshot.valueText) \(snapshot.unitText), \(snapshot.trendLabel), \(snapshot.zoneLabel), from \(snapshot.sourceName)"
        if stale {
            summary += ", reading may be out of date"
        }
        return summary
    }
}

// MARK: - Previews

#Preview("Now") {
    WatchNowPage(snapshot: .placeholder)
}

#Preview("Now · stale") {
    var stale = GlucoseSnapshot.placeholder
    stale.isStale = true
    return WatchNowPage(snapshot: stale)
}

#Preview("Glucose") {
    WatchGlucosePage(snapshot: .placeholder)
}

#Preview("Treat low") {
    WatchTreatLowPage()
}

#Preview("Insulin") {
    WatchQuickEntryPage(
        title: "Insulin", systemImage: "syringe", kind: "insulin",
        unit: "U", values: [1, 2, 4, 6], tint: Theme.accent
    )
}

#Preview("Carbs") {
    WatchQuickEntryPage(
        title: "Carbs", systemImage: "fork.knife", kind: "carbs",
        unit: "g", values: [20, 40, 60], tint: Theme.zoneHigh
    )
}

#Preview("Emergency") {
    WatchEmergencyPage()
}

#Preview("Full app") {
    WatchRootView(model: WatchModel())
}
