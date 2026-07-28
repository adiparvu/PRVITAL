import SwiftUI

/// The dashboard's customisable deck: which cards show, in what order.
///
/// The hero, quick actions and the safety banners (sick day, sensor) are fixed —
/// everything below them is a `DashboardCard` the user can reorder and toggle
/// from the "Customize page" screen. The chosen order is persisted in
/// `Preferences`; cards added in future builds append to the end automatically.
enum DashboardCard: String, CaseIterable, Identifiable, Codable {
    case companion
    case trend
    case lessons
    /// One whole: today's time-in-range + outlook, the goals/streak row and
    /// the daily rings, folded into a single card (the separate `goals` and
    /// `rings` cards were removed; `order(from:)` drops their persisted ids).
    case today
    case schedule
    /// One whole: the on-board figures, today's logged-events timeline and the
    /// Recent tiles (the separate `onBoard` and `recent` cards were removed).
    case timeline

    var id: String { rawValue }

    /// Labels reuse the cards' own existing catalog keys.
    var label: LocalizedStringKey {
        switch self {
        case .companion: "Daily companion"
        case .trend: "Trend"
        case .lessons: "Contextual lessons"
        case .today: "Today"
        case .schedule: "Logging schedule"
        case .timeline: "Today's log"
        }
    }

    var symbol: String {
        switch self {
        case .companion: "sun.max"
        case .trend: "waveform.path.ecg"
        case .lessons: "book"
        case .today: "clock"
        case .schedule: "clock.badge.checkmark"
        case .timeline: "list.bullet.rectangle"
        }
    }

    /// Resolves a persisted order: keeps the user's sequence, drops unknown
    /// entries, and appends any card the stored order doesn't know about yet.
    static func order(from raw: [String]) -> [DashboardCard] {
        var resolved = raw.compactMap(DashboardCard.init(rawValue:))
        for card in allCases where !resolved.contains(card) {
            resolved.append(card)
        }
        return resolved
    }
}

/// "Customize page": drag to reorder the dashboard's cards, toggle them on/off.
/// The companion and lessons toggles drive their existing preferences (the same
/// switches Appearance shows); every other card toggles the hidden set.
struct DashboardCustomizeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = env.preferences
        let order = DashboardCard.order(from: prefs.dashboardCardOrder)

        NavigationStack {
            List {
                Section {
                    ForEach(order) { card in
                        HStack(spacing: 12) {
                            PrvioIconTile(systemImage: card.symbol)
                            Text(card.label)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                            Toggle("", isOn: visibilityBinding(card, prefs: prefs))
                                .labelsHidden()
                                .tint(Theme.accent)
                        }
                        .padding(.vertical, 2)
                        // The Prvio row draws its own full-width hairline; the
                        // stock inset separator on top of it read as a foreign
                        // element (device feedback: "doesn't match the app").
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        var current = order
                        current.move(fromOffsets: from, toOffset: to)
                        prefs.dashboardCardOrder = current.map(\.rawValue)
                        Haptics.play(.selection)
                    }
                } header: {
                    Text("Cards on Home")
                        .prvioSectionHeader()
                } footer: {
                    Text("Drag to reorder. The glucose ring, quick actions and safety banners always stay at the top.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .prvioListRow()
            }
            .listSectionSpacing(.compact)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("Customize page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func visibilityBinding(_ card: DashboardCard, prefs: Preferences) -> Binding<Bool> {
        switch card {
        case .companion:
            Binding(get: { prefs.showDailyCompanion },
                    set: { prefs.showDailyCompanion = $0; Haptics.play(.selection) })
        case .lessons:
            Binding(get: { prefs.showContextualLessons },
                    set: { prefs.showContextualLessons = $0; Haptics.play(.selection) })
        default:
            Binding(get: { !prefs.dashboardHiddenCards.contains(card.rawValue) },
                    set: { visible in
                        var hidden = Set(prefs.dashboardHiddenCards)
                        if visible { hidden.remove(card.rawValue) } else { hidden.insert(card.rawValue) }
                        prefs.dashboardHiddenCards = Array(hidden).sorted()
                        Haptics.play(.selection)
                    })
        }
    }
}
