import SwiftUI
import SwiftData

/// A gallery of earned and in-progress achievements. Reads the user's records,
/// evaluates the milestones, folds any new unlocks into the (monotonic) store,
/// and renders a badge grid with progress toward the ones not yet earned.
struct AchievementsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var readings: [GlucoseReading]
    @Query private var meals: [CarbEntry]
    @Query private var activity: [ActivityEntry]

    init() {
        // Milestones look back about a year; cap at ~400 days so several imported
        // years don't all load when opening Achievements.
        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date())
            ?? Date().addingTimeInterval(-400 * 86_400)
        _readings = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                          sort: \.timestamp, order: .reverse)
        _meals = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
    }

    @State private var store = AchievementStore()

    private var challengeInputs: ChallengeInputs {
        ChallengeInputsBuilder.make(
            readings: readings, meals: meals, activity: activity,
            thresholds: env.preferences.thresholds,
            goalFraction: env.preferences.glucoseGoals.targetTIRFraction)
    }

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
                challengesCard(challengeInputs)
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

    private func challengesCard(_ inputs: ChallengeInputs) -> some View {
        let done = WeeklyChallengeEngine.completedCount(inputs)
        let total = WeeklyChallengeID.allCases.count
        let accessory = AnyView(
            Text("\(done)/\(total)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(done == total ? Theme.zoneInRange : Theme.textSecondary)
                .contentTransition(.numericText())
        )
        return SectionCard("This week's challenges", systemImage: "flag.checkered", accessory: accessory) {
            VStack(spacing: 14) {
                ForEach(WeeklyChallengeEngine.catalog) { challenge in
                    ChallengeRow(
                        challenge: challenge,
                        progress: WeeklyChallengeEngine.progress(challenge.id, inputs),
                        complete: WeeklyChallengeEngine.isComplete(challenge.id, inputs))
                }
            }
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

/// One weekly-challenge row: icon, title, a progress bar and current/target.
private struct ChallengeRow: View {
    let challenge: WeeklyChallenge
    let progress: (current: Int, target: Int)
    let complete: Bool

    private var tint: Color { complete ? Theme.zoneInRange : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : challenge.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(challenge.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(progress.current)/\(progress.target)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
                ProgressView(value: Double(progress.current), total: Double(max(progress.target, 1)))
                    .tint(tint)
                Text(challenge.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(challenge.title), \(progress.current) of \(progress.target)\(complete ? String(localized: ", complete") : "")")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AchievementsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
