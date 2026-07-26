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

    @Environment(\.modelContext) private var context
    @State private var store = AchievementStore()
    @State private var showBadgeInfo = false
    // This week's Apple Health exercise minutes by day, so the "Get moving"
    // challenge counts Apple Watch activity, not only logged sessions.
    @State private var healthExercise: [DailyMetric] = []

    private var challengeInputs: ChallengeInputs {
        ChallengeInputsBuilder.make(
            readings: readings, meals: meals, activity: activity,
            healthExercise: healthExercise,
            thresholds: env.preferences.thresholds,
            goalFraction: env.preferences.glucoseGoals.targetTIRFraction)
    }

    private var inputs: AchievementInputs {
        var inputs = AchievementInputsBuilder.make(
            readings: readings, meals: meals,
            thresholds: env.preferences.thresholds,
            goalFraction: env.preferences.glucoseGoals.targetTIRFraction)
        // Lifetime counts for the evolving badges — cheap fetchCounts, no rows.
        inputs.loggedActivities = (try? context.fetchCount(FetchDescriptor<ActivityEntry>())) ?? 0
        inputs.loggedNotes = (try? context.fetchCount(FetchDescriptor<ObservationEntry>())) ?? 0
        inputs.loggedKetones = (try? context.fetchCount(FetchDescriptor<KetoneReading>())) ?? 0
        inputs.sensorSessions = (try? context.fetchCount(FetchDescriptor<SensorSession>())) ?? 0
        return inputs
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let inputs = self.inputs
        let standings = BadgeEvaluator.standings(inputs)
        let points = standings.reduce(0) { $0 + $1.points }
        let earnedTiers = standings.reduce(0) { $0 + (($1.earnedIndex.map { $0 + 1 }) ?? 0) }
        let totalTiers = BadgeCatalog.families.reduce(0) { $0 + $1.thresholds.count }

        return ScrollView {
            VStack(spacing: 18) {
                header(points: points, earnedTiers: earnedTiers, totalTiers: totalTiers)
                communityCard(points: points, badges: earnedTiers)
                challengesCard(challengeInputs)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(standings) { standing in
                        BadgeFamilyCard(standing: standing)
                    }
                }
            }
            .padding()
        }
        .prvitalTabBackground()
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.light)
                    showBadgeInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How badges work")
            }
        }
        .sheet(isPresented: $showBadgeInfo) { BadgeInfoView() }
        .task {
            // A week fits in ~8 daily buckets (today + up to 7 prior days).
            healthExercise = await env.healthKit.dailyMetric(.exercise, days: 8)
        }
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

    /// The doorway to the community leaderboard, carrying the live score.
    private func communityCard(points: Int, badges: Int) -> some View {
        NavigationLink {
            CommunityView(points: points, badges: badges)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD9A521))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0xD9A521).opacity(0.16), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(env.preferences.community.enabled
                         ? String(localized: "See where you rank — country, continent, global.")
                         : String(localized: "Join the leaderboard and share your wins."))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Community leaderboard")
    }

    private func header(points: Int, earnedTiers: Int, totalTiers: Int) -> some View {
        let fraction = totalTiers > 0 ? Double(earnedTiers) / Double(totalTiers) : 0
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(points)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("points")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ProgressView(value: fraction)
                .tint(Theme.accent)
            Text("\(earnedTiers) of \(totalTiers) badge levels earned")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
            Text("Small, steady wins add up. Keep going.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(points) points. \(earnedTiers) of \(totalTiers) badge levels earned")
    }
}

// MARK: - Evolving badge card

/// One family's card: the seal in the current tier's colour, the tier chip and
/// the live progress toward the next level.
private struct BadgeFamilyCard: View {
    let standing: BadgeStanding

    private var tint: Color {
        standing.earnedTier.map { Color(hex: $0.colorHex) } ?? Theme.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(standing.earnedTier != nil ? tint.opacity(0.2) : Theme.hairline.opacity(0.6))
                    .frame(width: 52, height: 52)
                Image(systemName: standing.family.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(standing.earnedTier != nil ? tint : Theme.textTertiary)
                if standing.earnedTier != nil {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(tint)
                        .background(Circle().fill(Theme.surface).frame(width: 15, height: 15))
                        .offset(x: 20, y: -18)
                }
            }
            .accessibilityHidden(true)

            Text(standing.family.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let tier = standing.earnedTier {
                Text(tier.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: .capsule)
                    .foregroundStyle(tint)
            } else {
                Text("Locked")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            if let next = standing.nextThreshold {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: standing.progressToNext)
                        .tint(Theme.accent)
                    Text("\(standing.count) / \(next)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            } else {
                Text("Max level")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let title = standing.family.title
        if let tier = standing.earnedTier, let next = standing.nextThreshold {
            return String(localized: "\(title), \(tier.displayName). \(standing.count) of \(next) toward the next level.")
        }
        if let tier = standing.earnedTier {
            return String(localized: "\(title), \(tier.displayName). Max level.")
        }
        let next = standing.nextThreshold ?? 0
        return String(localized: "\(title), locked. \(standing.count) of \(next).")
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
