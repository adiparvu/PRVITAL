import SwiftUI

/// The Learn hub: actionable diabetes rules, a short encyclopedia and
/// diabetes-friendly recipes. All general education — never medical advice.
struct LearnView: View {
    private let rules = LearnLibrary.rules
    private let articles = LearnLibrary.articles
    private let recipes = LearnLibrary.recipes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    rulesSection.appearTransition(delay: 0)
                    sickDaySection.appearTransition(delay: 0.06)
                    articlesSection.appearTransition(delay: 0.12)
                    recipesSection.appearTransition(delay: 0.18)
                    LearnDisclaimerCard().appearTransition(delay: 0.24)
                }
                .padding()
            }
            .prvitalTabBackground()
            .navigationTitle("Learn")
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
                Text(rule.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(rule.tagline).font(.caption).foregroundStyle(Theme.textSecondary)
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
        SectionCard("Encyclopedia", systemImage: "book.fill") {
            VStack(spacing: 0) {
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    NavigationLink { ArticleDetailView(article: article) } label: { articleRow(article) }
                        .buttonStyle(PressableCardStyle())
                    if index < articles.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                }
            }
        }
    }

    private func articleRow(_ article: EncyclopediaArticle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: article.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(article.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
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
                Text(recipe.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(recipe.summary).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
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
            Text(LearnDisclaimer.text)
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
                    Text(rule.detail)
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
        .navigationTitle(rule.title)
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
                Text(rule.title).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text(rule.tagline).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}

struct ArticleDetailView: View {
    let article: EncyclopediaArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: article.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accentSoft, in: .circle)
                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(article.sections) { section in
                    SectionCard(LocalizedStringKey(section.heading)) {
                        Text(section.body)
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
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourcesCard: some View {
        SectionCard("Sources", systemImage: "text.book.closed") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(article.sources, id: \.self) { source in
                    Label(source, systemImage: "circle.fill")
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
                Text(recipe.summary)
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
                                Text(tag)
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
                            Label(item, systemImage: "circle.fill")
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
        .navigationTitle(recipe.name)
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
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
    Label(text, systemImage: "text.book.closed")
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

#Preview {
    LearnView()
        .environment(AppEnvironment.preview())
}
