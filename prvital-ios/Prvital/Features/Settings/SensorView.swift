import SwiftUI
import SwiftData

/// Tracks the current continuous-glucose-sensor session: its warm-up and the
/// countdown to expiry. Dexcom Share and similar feeds don't expose the session
/// start, so the user marks when they insert a sensor.
struct SensorView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \SensorSession.startDate, order: .reverse) private var sessions: [SensorSession]
    @State private var showingStart = false

    private var current: SensorSession? { sessions.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let current {
                    SensorStatusCard(session: current)
                } else {
                    EmptyStateView(
                        systemImage: "sensor.tag.radiowaves.forward",
                        title: "No sensor tracked",
                        message: "Mark when you insert a sensor to see its warm-up and a countdown to when it needs replacing."
                    )
                    .glassCard()
                }

                Button {
                    Haptics.play(.selection)
                    showingStart = true
                } label: {
                    Label("Start a new sensor", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingStart) { StartSensorSheet() }
    }
}

/// A card summarising a sensor session's phase and countdown.
struct SensorStatusCard: View {
    let session: SensorSession

    private var status: SensorStatus {
        SensorSessionEvaluator.status(start: session.startDate, kind: session.kind, now: Date())
    }

    var body: some View {
        let status = self.status
        return SectionCard(LocalizedStringKey(session.kind.displayName), systemImage: "sensor.tag.radiowaves.forward") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: SensorStatusStyle.icon(status.phase))
                        .font(.title2)
                        .foregroundStyle(SensorStatusStyle.tint(status.phase))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SensorStatusStyle.title(status.phase))
                            .font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(SensorStatusStyle.detail(status))
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }

                ProgressView(value: status.progress)
                    .tint(SensorStatusStyle.tint(status.phase))

                Text("Inserted \(session.startDate.formatted(date: .abbreviated, time: .shortened)) · expires \(session.expiryDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Shared styling for a sensor phase.
enum SensorStatusStyle {
    static func icon(_ phase: SensorPhase) -> String {
        switch phase {
        case .warmup: return "hourglass"
        case .active: return "checkmark.seal.fill"
        case .expiringSoon: return "exclamationmark.triangle.fill"
        case .expired: return "xmark.seal.fill"
        }
    }
    static func tint(_ phase: SensorPhase) -> Color {
        switch phase {
        case .warmup: return Theme.accent
        case .active: return Theme.zoneInRange
        case .expiringSoon: return Theme.zoneWarning
        case .expired: return Theme.zoneCritical
        }
    }
    static func title(_ phase: SensorPhase) -> LocalizedStringKey {
        switch phase {
        case .warmup: return "Warming up"
        case .active: return "Active"
        case .expiringSoon: return "Expiring soon"
        case .expired: return "Expired"
        }
    }
    static func detail(_ status: SensorStatus) -> String {
        switch status.phase {
        case .warmup: return "Ready in \(durationText(status.timeRemaining))"
        case .active, .expiringSoon: return "\(durationText(status.timeRemaining)) left"
        case .expired: return "Replace your sensor"
        }
    }
    /// A compact "2d 4h" / "3h 10m" / "20m" duration.
    static func durationText(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

/// Marks the start of a new sensor session.
struct StartSensorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SensorKind = .dexcomG7
    @State private var start = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sensor", selection: $kind) {
                        ForEach(SensorKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    DatePicker("Inserted", selection: $start, in: ...Date())
                } footer: {
                    Text("Prvital counts the warm-up and the wear time from here, and shows a countdown until you need to replace it.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
            }
            .navigationTitle("New sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        env.entryStore.startSensorSession(kind: kind, start: start)
                        Haptics.play(.success)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { SensorView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
