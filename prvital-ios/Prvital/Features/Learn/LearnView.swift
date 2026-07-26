import SwiftUI

/// The Learn hub: actionable diabetes rules, a short encyclopedia and
/// diabetes-friendly recipes. All general education — never medical advice.
struct LearnView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules = LearnLibrary.rules
    private let articles = LearnLibrary.articles
    private let recipes = LearnLibrary.recipes

    /// Reading progress, persisted on-device as a tab-joined list of article IDs.
    /// `ArticleDetailView` writes to the same key, so returning here re-renders the
    /// checkmarks and the count without any manual notification.
    @AppStorage("learn.readArticleIDs") private var readStore: String = ""
    private var progress: LearnProgress { LearnProgress.decode(readStore) }
    private var articleIDs: [String] { articles.map(\.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    continueCard.appearTransition(delay: 0)
                    rulesSection.appearTransition(delay: 0.06)
                    sickDaySection.appearTransition(delay: 0.12)
                    articlesSection.appearTransition(delay: 0.18)
                    recipesSection.appearTransition(delay: 0.24)
                    LearnDisclaimerCard().appearTransition(delay: 0.3)
                }
                .padding()
            }
            .prvitalTabBackground()
            .navigationTitle("Learn")
            // Presented as a sheet from Insights — without this the only way
            // back was the swipe-down nobody discovers (device feedback:
            // "it needs a back button").
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.play(.light)
                        dismiss()
                    }
                }
            }
        }
    }

    /// The academy's guiding hand: a hero card that points to the next unread
    /// article — a gentle "read this next" — and turns into a small celebration
    /// once the whole encyclopedia is read.
    @ViewBuilder private var continueCard: some View {
        if articles.isEmpty {
            EmptyView()
        } else if let nextID = progress.firstUnread(among: articleIDs),
                  let next = articles.first(where: { $0.id == nextID }) {
            NavigationLink { ArticleDetailView(article: next) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "graduationcap.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 46, height: 46)
                        .background(Theme.accentSoft, in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.readCount(among: articleIDs) == 0 ? "Start learning" : "Continue learning")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .textCase(.uppercase)
                        Text(LocalizedStringKey(next.title))
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20, padding: 14)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardStyle())
        } else {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.zoneInRange)
                    .frame(width: 46, height: 46)
                    .background(Theme.zoneInRange.opacity(0.15), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Academy complete").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("You've read every article").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20, padding: 14)
            .accessibilityElement(children: .combine)
        }
    }

    private var rulesSection: some View {
        SectionCard("Rules to live by", systemImage: "list.number") {
            VStack(spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    NavigationLink { RuleDetailView(rule: rule) } label: { ruleRow(rule) }
                        .buttonStyle(PressableCardStyle())
                    if index < rules.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                }
            }
        }
    }

    private func ruleRow(_ rule: DiabetesRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(rule.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(rule.tagline)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var sickDaySection: some View {
        SectionCard("When you're unwell", systemImage: "cross.case.fill") {
            NavigationLink { SickDayView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bandage.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.zoneWarning)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sick-day mode").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("The rules for managing diabetes through illness").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private var articlesSection: some View {
        SectionCard("Encyclopedia", systemImage: "book.fill", accessory: encyclopediaAccessory) {
            VStack(spacing: 0) {
                if !articles.isEmpty {
                    LearnProgressBar(fraction: progress.fraction(among: articleIDs))
                        .padding(.bottom, 12)
                }
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    NavigationLink { ArticleDetailView(article: article) } label: {
                        articleRow(article, isRead: progress.isRead(article.id))
                    }
                    .buttonStyle(PressableCardStyle())
                    if index < articles.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                }
            }
        }
    }

    /// A compact "read / total" tally in the section header — the visible cue that
    /// the encyclopedia is a library to work through, not just a flat list.
    private var encyclopediaAccessory: AnyView {
        let read = progress.readCount(among: articleIDs)
        return AnyView(
            Text(verbatim: "\(read)/\(articles.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(read == articles.count && !articles.isEmpty ? Theme.zoneInRange : Theme.textSecondary)
                .monospacedDigit()
                .accessibilityLabel(Text("\(read) of \(articles.count) read"))
        )
    }

    private func articleRow(_ article: EncyclopediaArticle, isRead: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: article.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(article.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(article.summary)).font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if isRead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.zoneInRange)
                    .accessibilityLabel(Text("Read"))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var recipesSection: some View {
        SectionCard("Diabetes-friendly recipes", systemImage: "fork.knife") {
            VStack(spacing: 0) {
                ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                    NavigationLink { RecipeDetailView(recipe: recipe) } label: { recipeRow(recipe) }
                        .buttonStyle(PressableCardStyle())
                    if index < recipes.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                }
            }
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: recipe.symbol)
                .font(.title3)
                .foregroundStyle(Theme.zoneInRange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(recipe.name)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(recipe.summary)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(recipe.carbsPerServingGrams.formatted(.number.precision(.fractionLength(0)))) g")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.zoneHigh)
                Text("per serving").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// The shared not-medical-advice note.
struct LearnDisclaimerCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(LearnDisclaimer.text))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail screens

struct RuleDetailView: View {
    let rule: DiabetesRule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SectionCard("Steps", systemImage: "checklist") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(rule.steps.enumerated()), id: \.offset) { index, step in
                            LearnStepRow(number: index + 1, text: step)
                        }
                    }
                }
                SectionCard("Good to know", systemImage: "lightbulb.fill") {
                    Text(LocalizedStringKey(rule.detail))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                sourceNote(rule.source)
                LearnDisclaimerCard()
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(LocalizedStringKey(rule.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: rule.symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .frame(width: 60, height: 60)
                .background(Theme.accentSoft, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(rule.title)).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(rule.tagline)).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}

struct ArticleDetailView: View {
    let article: EncyclopediaArticle

    /// Same key as `LearnView` — opening an article marks it read, and the hub
    /// reflects it the moment the reader navigates back.
    @AppStorage("learn.readArticleIDs") private var readStore: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: article.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accentSoft, in: .circle)
                    Text(LocalizedStringKey(article.summary))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(article.sections) { section in
                    SectionCard(LocalizedStringKey(section.heading)) {
                        Text(LocalizedStringKey(section.body))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                sourcesCard
                LearnDisclaimerCard()
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(LocalizedStringKey(article.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { markRead() }
    }

    /// Records this article as read the first time it's opened. Cheap and idempotent:
    /// only writes when the ID isn't already stored.
    private func markRead() {
        var progress = LearnProgress.decode(readStore)
        guard !progress.isRead(article.id) else { return }
        progress.markRead(article.id)
        readStore = progress.encoded()
    }

    private var sourcesCard: some View {
        SectionCard("Sources", systemImage: "text.book.closed") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(article.sources, id: \.self) { source in
                    Label(LocalizedStringKey(source), systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RecipeDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let recipe: Recipe
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(LocalizedStringKey(recipe.summary))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    statPill("\(recipe.carbsPerServingGrams.formatted(.number.precision(.fractionLength(0)))) g", "carbs / serving", Theme.zoneHigh)
                    statPill("\(recipe.servings)", recipe.servings == 1 ? "serving" : "servings", Theme.accent)
                    statPill("\(recipe.prepMinutes) min", "prep", Theme.zoneInRange)
                }

                if !recipe.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recipe.tags, id: \.self) { tag in
                                Text(LocalizedStringKey(tag))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Theme.accentSoft, in: .capsule)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }

                SectionCard("Ingredients", systemImage: "basket.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients, id: \.self) { item in
                            Label(LocalizedStringKey(item), systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard("Method", systemImage: "list.number") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            LearnStepRow(number: index + 1, text: step)
                        }
                    }
                }

                logButton
                LearnDisclaimerCard()
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(LocalizedStringKey(recipe.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var logButton: some View {
        Button {
            env.entryStore.addCarbs(
                grams: recipe.carbsPerServingGrams,
                mealType: .lunch,
                foodDescription: recipe.name
            )
            Haptics.play(.success)
            withAnimation(.snappy) { logged = true }
        } label: {
            Label(logged ? "Logged a serving" : "Log carbs for a serving",
                  systemImage: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(logged ? Theme.zoneInRange : Theme.accent)
        .disabled(logged)
    }

    private func statPill(_ value: String, _ caption: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(tint)
            Text(caption).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16, padding: 8)
    }
}

// MARK: - Shared bits

/// A numbered step with a tinted badge.
struct LearnStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accentSoft, in: .circle)
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// A slim capsule progress bar for the encyclopedia — the "how far through the
/// library am I" cue. Purely decorative (the header count carries the number for
/// VoiceOver), animated so it slides forward when a new article is marked read.
private struct LearnProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accentSoft)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A tiny dot bullet for lists.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(Theme.textTertiary)
            configuration.title
        }
    }
}

private func sourceNote(_ text: String) -> some View {
    Label(LocalizedStringKey(text), systemImage: "text.book.closed")
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

#Preview {
    LearnView()
        .environment(AppEnvironment.preview())
}
