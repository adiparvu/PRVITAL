import SwiftUI
import SwiftData

/// Identifies which full editor to present. Public so any screen can drive an
/// editor sheet with `.sheet(item:)`.
enum EntryEditorKind: String, Identifiable {
    case glucose, insulin, carbs, activity, observation
    var id: String { rawValue }

    /// Localized row title. (`LocalizedStringKey` so the catalog translates it —
    /// a plain `String` here once shipped the rows untranslated.)
    var titleKey: LocalizedStringKey {
        switch self {
        case .glucose: return "Glucose"
        case .insulin: return "Insulin"
        case .carbs: return "Carbs"
        case .activity: return "Activity"
        case .observation: return "Observation"
        }
    }
    /// One-line description under the row title.
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .glucose: return "Log a reading"
        case .insulin: return "Dose & type"
        case .carbs: return "Meal & food"
        case .activity: return "Movement & sport"
        case .observation: return "Notes & symptoms"
        }
    }
    var symbol: String {
        switch self {
        case .glucose: return "drop.fill"
        case .insulin: return "syringe.fill"
        case .carbs: return "fork.knife"
        case .activity: return "figure.walk"
        case .observation: return "note.text"
        }
    }
    var tint: Color {
        switch self {
        case .glucose: return Theme.zoneCritical
        case .insulin: return Theme.accent
        case .carbs: return Theme.zoneHigh
        case .activity: return Theme.zoneInRange
        case .observation: return Theme.textSecondary
        }
    }
}

/// Presents the editor for a given kind — used by the Add sheet's rows and by
/// the deep links from the Island/Control Center buttons.
struct EntryEditor: View {
    let kind: EntryEditorKind
    var body: some View {
        switch kind {
        case .glucose: GlucoseEntrySheet()
        case .insulin: InsulinEntrySheet()
        case .carbs: CarbEntrySheet()
        case .activity: ActivityEntrySheet()
        case .observation: ObservationEntrySheet()
        }
    }
}

/// The add-entry sheet, Dexcom-style (device-approved reference): the current
/// glucose stays on top, and below it a single clean list — one row per thing
/// you can log, each with a title, a one-line explanation and a ⊕. No preset
/// chips, no favorites wall; every row opens its full editor.
struct QuickEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var recentInsulin: [InsulinDose]

    @State private var editor: EntryEditorKind?
    @State private var showBolusCalculator = false
    @State private var showRuleOf15 = false
    @State private var showKetones = false
    /// The free-typed sentence in the natural-language card.
    @State private var phraseText = ""
    /// The user's repeat meals ("the usual breakfast"), one tap to re-log.
    @State private var combos: [MealCombo] = []
    /// Workout mode: live banner vs start button.
    @State private var exerciseActive = ExerciseMode.isActive()
    @State private var showExerciseStart = false

    init() {
        // Only the doses that can still carry insulin-on-board — bounded.
        let cutoff = Date().addingTimeInterval(-8 * 3600)
        _recentInsulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff })
    }

    // MARK: Context

    /// The display-ready snapshot the widgets use — self-contained and cheap.
    private var snapshot: GlucoseSnapshot { SharedStore.load() }
    private var hasLiveReading: Bool { snapshot.updatedAt > .distantPast }
    private var currentZone: GlucoseZone {
        env.preferences.thresholds.zone(forMgdL: snapshot.mgdL)
    }
    private var showTreatLow: Bool {
        hasLiveReading && !snapshot.isStale && currentZone.isHypo
    }

    private var bolusParameters: BolusParameters { env.preferences.bolusParameters }

    /// Live insulin-on-board — the number to glance at before doubling a dose.
    private var insulinOnBoard: Double {
        guard bolusParameters.isValid else { return 0 }
        return InsulinMath.activeInsulin(doses: recentInsulin, at: Date(), parameters: bolusParameters)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if hasLiveReading {
                        contextBanner.appearTransition(delay: 0)
                    }
                    if showTreatLow {
                        treatLowButton.appearTransition(delay: 0.03)
                    }
                    naturalLogCard.appearTransition(delay: 0.05)
                    if !combos.isEmpty {
                        combosRow.appearTransition(delay: 0.055)
                    }
                    exerciseCard.appearTransition(delay: 0.058)
                    entryList.appearTransition(delay: 0.06)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Add entry")
            .task { loadCombos() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editor) { EntryEditor(kind: $0) }
            // Wrapped in its own stack: presented bare it had no bar and no way
            // out (device feedback) — pushed from Settings/Dashboard it already
            // gets a back button from the surrounding stack.
            .sheet(isPresented: $showBolusCalculator) {
                NavigationStack {
                    BolusCalculatorView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showBolusCalculator = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showRuleOf15) { RuleOf15Sheet() }
            .sheet(isPresented: $showKetones) { LogKetoneSheet() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Exercise mode

    /// Start a workout (raised low limit for its duration, auto-logged at the
    /// end) — or, while one runs, the live banner with elapsed time and Stop.
    @ViewBuilder private var exerciseCard: some View {
        if exerciseActive, let started = ExerciseMode.startedAt {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.zoneInRange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout running")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(started, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    Haptics.play(.success)
                    ExerciseMode.finish(entryStore: env.entryStore, force: true)
                    exerciseActive = false
                } label: {
                    Text("Stop & log")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.zoneInRange, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        } else {
            Button {
                Haptics.play(.selection)
                showExerciseStart = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.zoneInRange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a workout")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("raised low alert while you move, logged when you stop")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassCard()
            .sheet(isPresented: $showExerciseStart) {
                ExerciseStartSheet {
                    exerciseActive = true
                }
            }
        }
    }

    // MARK: Frequent combos

    /// "The usual" row: repeat meals detected from the last month, re-logged
    /// (grams + the usual dose) in one tap.
    private var combosRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(combos) { combo in
                    Button {
                        logCombo(combo)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2.weight(.bold))
                            Text(comboLabel(combo))
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.accentSoft, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func comboLabel(_ combo: MealCombo) -> String {
        var label = combo.foodDescription ?? String(localized: "Meal")
        label += " \(Int(combo.grams.rounded())) g"
        if let units = combo.units {
            label += " + \(units.formatted(.number.precision(.fractionLength(0...1)))) U"
        }
        return label
    }

    private func logCombo(_ combo: MealCombo) {
        env.entryStore.addCarbs(grams: combo.grams,
                                mealType: suggestedMealType(),
                                foodDescription: combo.foodDescription)
        if let units = combo.units {
            env.entryStore.addInsulin(units: units)
        }
        Haptics.play(.success)
        dismiss()
    }

    /// One bounded fetch of the last month, folded into habit combos.
    private func loadCombos() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let carbs = (try? modelContext.fetch(FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff }))) ?? []
        let doses = (try? modelContext.fetch(FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= cutoff }))) ?? []
        combos = FrequentCombos.detect(
            meals: carbs.map { ($0.timestamp, $0.grams, $0.foodDescription) },
            doses: doses.map { ($0.timestamp, $0.units) })
    }

    // MARK: Natural-language log

    /// One typed sentence — "45g paste și 4 unități" — split on device into the
    /// entries it names, previewed as chips before anything is saved.
    @ViewBuilder private var naturalLogCard: some View {
        let phrase = QuickPhraseParser.parse(phraseText, unit: env.preferences.glucoseUnit)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(Theme.accent)
                TextField("Type it: e.g. 45g pasta and 4 units", text: $phraseText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commitPhrase(phrase) }
            }
            if !phrase.isEmpty {
                HStack(spacing: 8) {
                    if let mgdL = phrase.glucoseMgdL {
                        phraseChip(
                            GlucoseFormatting.labeled(mgdL: mgdL, unit: env.preferences.glucoseUnit),
                            symbol: "drop.fill")
                    }
                    if let grams = phrase.carbGrams {
                        phraseChip("\(Int(grams.rounded())) g", symbol: "fork.knife")
                    }
                    if let units = phrase.insulinUnits {
                        phraseChip("\(units.formatted(.number.precision(.fractionLength(0...1)))) U",
                                   symbol: "syringe.fill")
                    }
                    Spacer()
                    Button {
                        commitPhrase(phrase)
                    } label: {
                        Text("Log all")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.accent, in: .capsule)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(.snappy, value: phrase)
    }

    private func phraseChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentSoft, in: .capsule)
    }

    /// The meal slot the clock suggests — the free-text field never asks.
    private func suggestedMealType(now: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .morningSnack
        case 18..<22: return .dinner
        default: return .eveningSnack
        }
    }

    private func commitPhrase(_ phrase: QuickPhrase) {
        guard !phrase.isEmpty else { return }
        if let mgdL = phrase.glucoseMgdL {
            _ = env.entryStore.addGlucose(mgdL: mgdL)
        }
        if let grams = phrase.carbGrams {
            env.entryStore.addCarbs(
                grams: grams,
                mealType: suggestedMealType(),
                foodDescription: phrase.foodDescription)
        }
        if let units = phrase.insulinUnits {
            env.entryStore.addInsulin(units: units)
        }
        Haptics.play(.success)
        phraseText = ""
        dismiss()
    }

    // MARK: Context banner

    /// The current reading — kept on top by request — plus live IOB, so a
    /// second dose is never a surprise.
    private var contextBanner: some View {
        let tint = snapshot.isStale ? Color.gray : Color(hex: snapshot.zoneColorHex)
        return HStack(spacing: 12) {
            Image(systemName: snapshot.isStale ? "clock" : snapshot.trendSymbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(snapshot.valueText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(snapshot.isStale ? Theme.textSecondary : Theme.textPrimary)
                    Text(snapshot.unitText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 4) {
                    Text(snapshot.zoneLabel)
                    Text("·")
                    Text(snapshot.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if insulinOnBoard >= 0.05 {
                HStack(spacing: 4) {
                    Text("IOB")
                        .font(.caption2.weight(.semibold))
                    Text("\(insulinOnBoard.formatted(.number.precision(.fractionLength(1)))) U")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.accentSoft, in: .capsule)
                .accessibilityLabel("Insulin on board \(insulinOnBoard.formatted(.number.precision(.fractionLength(1)))) units")
            }
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var treatLowButton: some View {
        Button {
            Haptics.play(.warning)
            showRuleOf15 = true
        } label: {
            Label("Treat low (Rule of 15)", systemImage: "cross.case.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(currentZone.color)
        .accessibilityHint("Opens a guided low-glucose treatment")
    }

    // MARK: Entry list

    /// One glass container, divider-separated rows — the Dexcom event list.
    private var entryList: some View {
        VStack(spacing: 0) {
            ForEach(Array([EntryEditorKind.glucose, .insulin, .carbs, .activity, .observation].enumerated()),
                    id: \.element) { index, kind in
                if index > 0 { rowDivider }
                entryRow(symbol: kind.symbol, tint: kind.tint,
                         title: kind.titleKey, subtitle: kind.subtitleKey) {
                    editor = kind
                }
            }
            rowDivider
            entryRow(symbol: "drop.triangle.fill", tint: Theme.zoneWarning,
                     title: "Ketones", subtitle: "Blood or urine reading") {
                showKetones = true
            }
            if bolusParameters.isEnabled, bolusParameters.isValid {
                rowDivider
                entryRow(symbol: "function", tint: Theme.accent,
                         title: "Bolus calculator",
                         subtitle: "Suggests a dose from carbs, glucose, IOB & COB") {
                    showBolusCalculator = true
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 6)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.leading, 62)
    }

    /// A Dexcom-style event row: icon, title + one-line explanation, and the
    /// trailing ⊕ that says "this adds something".
    private func entryRow(symbol: String, tint: Color,
                          title: LocalizedStringKey, subtitle: LocalizedStringKey,
                          action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Theme.textPrimary.opacity(0.06), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return QuickEntrySheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}

/// Choosing the workout: type, planned length, and how far to raise the low
/// alert while it runs. Everything else is automatic.
private struct ExerciseStartSheet: View {
    let onStart: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var type: ActivityType = .walking
    @State private var minutes = 60
    @State private var raisedLow = 90.0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $type) {
                    ForEach([ActivityType.walking, .running, .gym, .cycling, .swimming], id: \.self) { option in
                        Label(option.label, systemImage: "figure.run").tag(option)
                    }
                }
                Picker("Planned length", selection: $minutes) {
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                    Text("90 min").tag(90)
                    Text("120 min").tag(120)
                }
                Picker("Low alert during it", selection: $raisedLow) {
                    Text(GlucoseFormatting.labeled(mgdL: 80, unit: env.preferences.glucoseUnit)).tag(80.0)
                    Text(GlucoseFormatting.labeled(mgdL: 90, unit: env.preferences.glucoseUnit)).tag(90.0)
                    Text(GlucoseFormatting.labeled(mgdL: 100, unit: env.preferences.glucoseUnit)).tag(100.0)
                }
            }
            .navigationTitle("Start a workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Haptics.play(.success)
                        ExerciseMode.start(type: type, minutes: minutes, raisedLowMgdL: raisedLow)
                        onStart()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
