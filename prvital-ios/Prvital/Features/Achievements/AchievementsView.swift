import SwiftUI
import SwiftData

/// A gallery of earned and in-progress achievements. Reads the user's records,
/// evaluates the milestones, folds any new unlocks into the (monotonic) store,
/// and renders a badge grid with progress toward the ones not yet earned.
struct AchievementsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var readings: [GlucoseReading]
    @Query private var meals: [CarbEntry]

    @State private var store = AchievementStore()

    private var inputs: AchievementInputs {
        AchievementInputsBuilder.make(
            readings: readings, meals: meals,
            thresholds: env.preferences.thresholds,
            goalFraction: env.preferences.glucoseGoals.targetTIRFraction)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let inputs = self.inputs
        // Union live unlocks with what's already been earned, so a badge won by a
        // stretch that later dipped still shows as earned.
        let earned = store.earned.union(AchievementEvaluator.unlocked(inputs))
        let earnedCount = AchievementID.allCases.filter { earned.contains($0) }.count

        return ScrollView {
            VStack(spacing: 18) {
                header(earned: earnedCount, total: AchievementID.allCases.count)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AchievementCatalog.all) { achievement in
                        AchievementCard(
                            achievement: achievement,
                            isEarned: earned.contains(achievement.id),
                            progress: AchievementEvaluator.progress(achievement.id, inputs)
                        )
                    }
                }
            }
            .padding()
        }
        .prvitalTabBackground()
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.record(unlocked: AchievementEvaluator.unlocked(inputs))
            store.markAllSeen()
        }
    }

    private func header(earned: Int, total: Int) -> some View {
        let fraction = total > 0 ? Double(earned) / Double(total) : 0
        return VStack(spacing: 10) {
            Text("\(earned) of \(total) earned")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            ProgressView(value: fraction)
                .tint(Theme.accent)
            Text("Small, steady wins add up. Keep going.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(earned) of \(total) achievements earned")
    }
}

// MARK: - Badge card

/// Tier accent colours — warm metallics that read the same in light and dark.
private extension AchievementTier {
    var color: Color {
        switch self {
        case .bronze: return Color(hex: 0xC17B48)
        case .silver: return Color(hex: 0x9AA3AD)
        case .gold: return Color(hex: 0xE0A100)
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }
}

private struct AchievementCard: View {
    let achievement: Achievement
    let isEarned: Bool
    let progress: (current: Int, target: Int)

    private var tint: Color { achievement.tier.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isEarned ? tint.opacity(0.18) : Theme.hairline.opacity(0.6))
                    .frame(width: 52, height: 52)
                Image(systemName: achievement.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isEarned ? tint : Theme.textTertiary)
                if isEarned {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(tint)
                        .background(Circle().fill(Theme.surface).frame(width: 15, height: 15))
                        .offset(x: 20, y: -18)
                }
            }
            .accessibilityHidden(true)

            Text(achievement.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(achievement.detail)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if isEarned {
                Text(achievement.tier.label)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: .capsule)
                    .foregroundStyle(tint)
            } else if progress.target > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: Double(progress.current), total: Double(progress.target))
                        .tint(Theme.accent)
                    Text("\(progress.current) / \(progress.target)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            } else {
                Text("Locked")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .opacity(isEarned ? 1 : 0.9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isEarned {
            return String(localized: "\(achievement.title), earned. \(achievement.detail)")
        }
        if progress.target > 1 {
            return String(localized: "\(achievement.title), \(progress.current) of \(progress.target). \(achievement.detail)")
        }
        return String(localized: "\(achievement.title), locked. \(achievement.detail)")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AchievementsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
