import SwiftUI
import SwiftData

/// The Alerts hub — one screen for every reactive alert Prvital can raise:
/// out-of-range levels, rate-of-change (rising / falling fast), signal loss
/// (no recent data), and a link to the sensor session. A live status card at the
/// top shows what the alerts see right now.
///
/// The out-of-range levels, escalation and snooze work exactly as before; this
/// screen adds the rate-of-change and signal-loss categories in the same place.
struct AlertsHubView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var readings: [GlucoseReading]

    /// A working copy, written back on change so the enable/disable side effects
    /// (permission request, stand-down) fire exactly once.
    @State private var prefs = AlertPreferences.default

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    init() {
        let windowStart = Calendar.current.date(byAdding: .minute, value: -60, to: Date())
            ?? Date().addingTimeInterval(-3600)
        _readings = Query(
            filter: #Predicate<GlucoseReading> { $0.timestamp >= windowStart },
            sort: \.timestamp, order: .reverse
        )
    }

    var body: some View {
        @Bindable var preferences = env.preferences
        Form {
            Section {
                AlertStatusCard(status: liveStatus)
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            }
            .glassListRow()

            Section {
                Toggle("Enable glucose alerts", isOn: $prefs.enabled)
            } footer: {
                Text("Get notified about your glucose while the app can sync a recent reading. Alerts are delivered as local notifications on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            if prefs.enabled {
                outOfRangeSection
                escalationSection(preferences: preferences)
                rateOfChangeSection
                signalLossSection
                missedBolusSection
                sensorSection
                snoozeSection
            }

            soundsSection
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .animation(.easeInOut(duration: 0.25), value: prefs.enabled)
        .animation(.easeInOut(duration: 0.25), value: prefs.riseRateEnabled)
        .animation(.easeInOut(duration: 0.25), value: prefs.fallRateEnabled)
        .animation(.easeInOut(duration: 0.25), value: prefs.signalLossEnabled)
        .animation(.easeInOut(duration: 0.25), value: env.preferences.criticalAlarm.escalationEnabled)
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefs = env.preferences.alerts }
        .onChange(of: prefs) { oldValue, newValue in
            env.preferences.alerts = newValue
            if newValue.enabled && !oldValue.enabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
            if (oldValue.enabled && !newValue.enabled) || (oldValue.urgentLow && !newValue.urgentLow) {
                CriticalAlarmScheduler.standDown()
            }
        }
        .onChange(of: env.preferences.criticalAlarm.escalationEnabled) { wasOn, isOn in
            if isOn {
                Task { _ = await env.notifications.requestAuthorization() }
            } else if wasOn {
                CriticalAlarmScheduler.standDown()
            }
        }
    }

    // MARK: - Sections

    private var outOfRangeSection: some View {
        Section {
            alertToggle(String(localized: "Urgent low"), String(localized: "below \(value(thresholds.veryLow))"), isOn: $prefs.urgentLow, tint: Theme.zoneCritical)
            alertToggle(String(localized: "Low"), String(localized: "below \(value(thresholds.targetLower))"), isOn: $prefs.low, tint: Theme.zoneWarning)
            alertToggle(String(localized: "High"), String(localized: "above \(value(thresholds.targetUpper))"), isOn: $prefs.high, tint: Theme.zoneHigh)
            alertToggle(String(localized: "Very high"), String(localized: "above \(value(thresholds.high))"), isOn: $prefs.urgentHigh, tint: Theme.zoneWarning)
        } header: {
            Text("Out of range")
        } footer: {
            Text("Uses the thresholds from Units & targets.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    @ViewBuilder
    private func escalationSection(preferences: Preferences) -> some View {
        if prefs.urgentLow {
            Section {
                Toggle("Repeat until acknowledged", isOn: Binding(
                    get: { preferences.criticalAlarm.escalationEnabled },
                    set: { preferences.criticalAlarm.escalationEnabled = $0 }
                ))
                .tint(Theme.zoneCritical)
                if preferences.criticalAlarm.escalationEnabled {
                    Picker("Repeat every", selection: Binding(
                        get: { preferences.criticalAlarm.repeatMinutes },
                        set: { preferences.criticalAlarm.repeatMinutes = $0 }
                    )) {
                        Text("3 minutes").tag(3)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                    }
                    Picker("Max repeats", selection: Binding(
                        get: { preferences.criticalAlarm.maxRepeats },
                        set: { preferences.criticalAlarm.maxRepeats = $0 }
                    )) {
                        Text("3").tag(3)
                        Text("6").tag(6)
                        Text("10").tag(10)
                    }
                }
            } header: {
                Text("Urgent low escalation")
            } footer: {
                Text("When an urgent low isn't acknowledged, it repeats on this schedule until you tap it, until a newer reading shows you back above the urgent-low threshold, or until the maximum repeats.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
    }

    private var rateOfChangeSection: some View {
        Section {
            alertToggle(String(localized: "Rising fast"), String(localized: "climbing quickly"), isOn: $prefs.riseRateEnabled, tint: Theme.zoneHigh)
            alertToggle(String(localized: "Falling fast"), String(localized: "dropping quickly"), isOn: $prefs.fallRateEnabled, tint: Theme.zoneWarning)
            if prefs.riseRateEnabled || prefs.fallRateEnabled {
                Stepper(value: $prefs.rateThresholdPerMinute, in: 1...6, step: 0.5) {
                    HStack {
                        Text("Trigger above")
                        Spacer()
                        Text("\(prefs.rateThresholdPerMinute.formatted(.number.precision(.fractionLength(1)))) mg/dL/min")
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Rate of change")
        } footer: {
            Text("Catch a steep rise or fall early, whatever the value. Around 2–3 mg/dL per minute matches the classic \"rising/falling fast\" trend arrows.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    private var signalLossSection: some View {
        Section {
            Toggle(isOn: $prefs.signalLossEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No recent readings").foregroundStyle(Theme.textPrimary)
                    Text("when data stops arriving").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            if prefs.signalLossEnabled {
                Picker("After", selection: $prefs.signalLossMinutes) {
                    Text("20 minutes").tag(20)
                    Text("25 minutes").tag(25)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                }
            }
        } header: {
            Text("Signal loss")
        } footer: {
            Text("Warns you once when no new glucose data has arrived for this long — a sensor dropout or a lost connection. Detection runs while the app is open or syncing in the background.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    private var missedBolusSection: some View {
        Section {
            Toggle(isOn: $prefs.missedBolusEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missed bolus").foregroundStyle(Theme.textPrimary)
                    Text("meal logged or rising, no dose recorded")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Bolus")
        } footer: {
            Text("A gentle nudge ~25 minutes after a logged meal that has no bolus around it — and when glucose climbs fast with nothing logged at all. For people who dose insulin at meals.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    private var sensorSection: some View {
        Section {
            NavigationLink {
                SensorView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.zoneInRange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sensor session").foregroundStyle(Theme.textPrimary)
                        Text("Warm-up & expiry countdown")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Sensor")
        } footer: {
            Text("Track your current sensor's warm-up and expiry so a change never catches you by surprise.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    /// Sound & vibration per category. Outside the `prefs.enabled` block on
    /// purpose: the reminders category applies even with glucose alerts off.
    private var soundsSection: some View {
        Section {
            ForEach(AlertSoundCategory.allCases) { category in
                NavigationLink {
                    AlertSoundPickerView(category: category)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(category.tint)
                            .frame(width: 28)
                        Text(category.title)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(env.preferences.alertSounds[keyPath: category.keyPath].summaryLabel)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Sounds & vibration")
        } footer: {
            Text("Choose how each kind of notification sounds on this device.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    private var snoozeSection: some View {
        Section {
            Stepper(value: $prefs.snoozeMinutes, in: 5...120, step: 5) {
                Text("Snooze repeats: \(prefs.snoozeMinutes) min")
                    .contentTransition(.numericText())
                    .animation(.snappy, value: prefs.snoozeMinutes)
            }
        } footer: {
            Text("The same alert won't repeat within this window. A change — such as low to urgent low, or a new direction — always alerts right away.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    // MARK: - Live status

    private var liveStatus: AlertLiveStatus {
        let now = Date()
        let active = readings.filter(\.isActive)
        guard let current = active.first else {
            return AlertLiveStatus(hasReading: false, valueText: "—", zone: nil,
                                   minutesAgo: nil, perMinute: nil, unit: unit)
        }
        let velocity = GlucoseTrendAnalyzer.velocity(active, now: now)
        let stale = now.timeIntervalSince(current.timestamp) > 20 * 60
        return AlertLiveStatus(
            hasReading: true,
            valueText: GlucoseFormatting.string(mgdL: current.valueMgdL, unit: unit),
            zone: thresholds.zone(forMgdL: current.valueMgdL, at: current.timestamp),
            minutesAgo: max(0, Int(now.timeIntervalSince(current.timestamp) / 60)),
            perMinute: stale ? nil : velocity?.mgdLPerMinute,
            unit: unit
        )
    }

    // MARK: - Helpers

    private func alertToggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(tint)
    }

    private func value(_ mgdL: Double) -> String {
        GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)
    }
}

// MARK: - Status model + card

/// A snapshot of what the alerts currently see: the latest value, its zone, how
/// fresh it is, and the measured rate of change.
private struct AlertLiveStatus {
    let hasReading: Bool
    let valueText: String
    let zone: GlucoseZone?
    let minutesAgo: Int?
    let perMinute: Double?
    let unit: GlucoseUnit

    var zoneColor: Color {
        switch zone {
        case .veryLow, .veryHigh: return Theme.zoneCritical
        case .low: return Theme.zoneWarning
        case .high: return Theme.zoneHigh
        case .inRange: return Theme.zoneInRange
        case nil: return Theme.textTertiary
        }
    }

    var freshnessColor: Color {
        guard let minutesAgo else { return Theme.textTertiary }
        if minutesAgo <= 10 { return Theme.zoneInRange }
        if minutesAgo <= 20 { return Theme.zoneHigh }
        return Theme.zoneCritical
    }

    var freshnessText: String {
        guard let minutesAgo else { return String(localized: "No readings yet") }
        return minutesAgo < 1 ? String(localized: "Updated just now")
                              : String(localized: "Updated \(minutesAgo) min ago")
    }

    /// A short rate description, e.g. "↑ 2.4 mg/dL/min" — nil when unknown.
    var rateText: String? {
        guard let perMinute else { return nil }
        let magnitude = abs(perMinute).formatted(.number.precision(.fractionLength(1)))
        if perMinute >= 0.3 { return "↑ \(magnitude) mg/dL/min" }
        if perMinute <= -0.3 { return "↓ \(magnitude) mg/dL/min" }
        return String(localized: "Steady")
    }
}

private struct AlertStatusCard: View {
    let status: AlertLiveStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(status.zoneColor.opacity(0.16)).frame(width: 52, height: 52)
                Text(status.hasReading ? status.valueText : "—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(status.zoneColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(status.freshnessColor).frame(width: 7, height: 7)
                    Text(status.freshnessText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let rateText = status.rateText {
                    Text(rateText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                } else if status.hasReading {
                    Text("Trend not available yet")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.freshnessText), \(status.rateText ?? "")")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AlertsHubView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
