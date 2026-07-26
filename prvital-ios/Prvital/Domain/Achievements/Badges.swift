import Foundation

/// Discord-style EVOLVING badges: one badge per family that upgrades through
/// tiers as the underlying count grows, instead of a flat one-shot list. Pure
/// data + pure evaluation, so the whole system is unit-testable; the legacy
/// `AchievementCatalog` stays untouched underneath (its store still drives the
/// celebration toasts).
enum BadgeTier: Int, CaseIterable, Comparable, Sendable {
    case bronze, silver, gold, platinum, diamond

    static func < (lhs: BadgeTier, rhs: BadgeTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .bronze: String(localized: "Bronze")
        case .silver: String(localized: "Silver")
        case .gold: String(localized: "Gold")
        case .platinum: String(localized: "Platinum")
        case .diamond: String(localized: "Diamond")
        }
    }

    /// Seal colour as 0xRRGGBB.
    var colorHex: UInt {
        switch self {
        case .bronze: 0xB0793C
        case .silver: 0x9BA6B5
        case .gold: 0xD9A521
        case .platinum: 0x7FD1C8
        case .diamond: 0x7FA8F0
        }
    }

    /// Points the tier is worth on the (upcoming) community leaderboard.
    var points: Int {
        switch self {
        case .bronze: 10
        case .silver: 25
        case .gold: 50
        case .platinum: 100
        case .diamond: 200
        }
    }
}

/// One evolving badge: what it counts, its symbol, and the count needed for
/// each tier (index 0 = bronze … index 4 = diamond; shorter arrays simply top
/// out earlier, and `tierOverride` lets a single-threshold badge sit at a
/// specific tier).
struct BadgeFamily: Identifiable, Equatable, Sendable {
    let id: BadgeFamilyID
    let title: String
    /// Per-tier description with the threshold interpolated ("Log %lld meals.").
    let detailFormat: String
    let symbol: String
    let thresholds: [Int]
    var tierOverride: BadgeTier?

    /// The tier a threshold index maps to.
    func tier(atIndex index: Int) -> BadgeTier {
        if let tierOverride { return tierOverride }
        return BadgeTier(rawValue: min(index, BadgeTier.diamond.rawValue)) ?? .bronze
    }
}

/// Stable identifiers; raw values may be persisted or uploaded, never rename.
enum BadgeFamilyID: String, CaseIterable, Sendable {
    case glucoseDays
    case meals
    case streak
    case perfectDays
    case tightDays
    case activities
    case notes
    case ketones
    case sensors
    case a1c
}

enum BadgeCatalog {
    static let families: [BadgeFamily] = [
        BadgeFamily(id: .glucoseDays, title: String(localized: "Data collector"),
                    detailFormat: String(localized: "Record glucose on %lld different days."),
                    symbol: "drop.fill", thresholds: [1, 7, 30, 90, 365]),
        BadgeFamily(id: .meals, title: String(localized: "Meal chronicler"),
                    detailFormat: String(localized: "Log %lld meals."),
                    symbol: "fork.knife", thresholds: [1, 25, 100, 500, 1000]),
        BadgeFamily(id: .streak, title: String(localized: "In-range streak"),
                    detailFormat: String(localized: "Meet your time-in-range goal %lld days in a row."),
                    symbol: "flame.fill", thresholds: [7, 14, 30, 60, 90]),
        BadgeFamily(id: .perfectDays, title: String(localized: "Perfect days"),
                    detailFormat: String(localized: "Spend %lld whole days 100%% in range."),
                    symbol: "star.circle.fill", thresholds: [1, 5, 15, 40, 100]),
        BadgeFamily(id: .tightDays, title: String(localized: "Steady days"),
                    detailFormat: String(localized: "Have %lld days mostly in the tight 70–140 range."),
                    symbol: "target", thresholds: [7, 21, 60, 120, 250]),
        BadgeFamily(id: .activities, title: String(localized: "On the move"),
                    detailFormat: String(localized: "Log %lld activities."),
                    symbol: "figure.walk", thresholds: [5, 25, 100, 250, 500]),
        BadgeFamily(id: .notes, title: String(localized: "Note taker"),
                    detailFormat: String(localized: "Write %lld notes."),
                    symbol: "square.and.pencil", thresholds: [5, 25, 100, 250, 500]),
        BadgeFamily(id: .ketones, title: String(localized: "Ketone aware"),
                    detailFormat: String(localized: "Log %lld ketone measurements."),
                    symbol: "testtube.2", thresholds: [1, 10, 30, 75, 150]),
        BadgeFamily(id: .sensors, title: String(localized: "Sensor keeper"),
                    detailFormat: String(localized: "Track %lld sensor sessions."),
                    symbol: "sensor.tag.radiowaves.forward", thresholds: [1, 5, 15, 40, 100]),
        BadgeFamily(id: .a1c, title: String(localized: "A1c on target"),
                    detailFormat: String(localized: "Reach an estimated A1c of 7.0%% or lower."),
                    symbol: "heart.text.square.fill", thresholds: [1], tierOverride: .gold),
    ]

    static func family(_ id: BadgeFamilyID) -> BadgeFamily {
        families.first { $0.id == id } ?? families[0]
    }
}

/// The evaluated state of one family: the raw count, the tier earned (if any),
/// and what's next.
struct BadgeStanding: Identifiable, Equatable, Sendable {
    let family: BadgeFamily
    let count: Int
    /// Index into `family.thresholds` of the highest tier reached; nil = none.
    let earnedIndex: Int?

    var id: BadgeFamilyID { family.id }
    var earnedTier: BadgeTier? { earnedIndex.map(family.tier(atIndex:)) }
    /// The next threshold to chase; nil once the badge is maxed out.
    var nextThreshold: Int? {
        let next = (earnedIndex.map { $0 + 1 }) ?? 0
        return next < family.thresholds.count ? family.thresholds[next] : nil
    }
    var isMaxed: Bool { earnedIndex == family.thresholds.count - 1 }
    /// Points from every tier reached so far in this family.
    var points: Int {
        guard let earnedIndex else { return 0 }
        return (0...earnedIndex).reduce(0) { $0 + family.tier(atIndex: $1).points }
    }
    /// 0…1 progress from the previous threshold toward the next.
    var progressToNext: Double {
        guard let next = nextThreshold else { return 1 }
        let base = earnedIndex.map { family.thresholds[$0] } ?? 0
        guard next > base else { return 1 }
        return min(1, max(0, Double(count - base) / Double(next - base)))
    }
}

enum BadgeEvaluator {
    /// The count that drives a family, from the shared inputs.
    static func count(for id: BadgeFamilyID, _ inputs: AchievementInputs) -> Int {
        switch id {
        case .glucoseDays: inputs.daysWithData
        case .meals: inputs.loggedMeals
        case .streak: inputs.bestStreakDays
        case .perfectDays: inputs.perfectDays
        case .tightDays: inputs.tightDays
        case .activities: inputs.loggedActivities
        case .notes: inputs.loggedNotes
        case .ketones: inputs.loggedKetones
        case .sensors: inputs.sensorSessions
        case .a1c: (inputs.bestGmi.map { $0 <= 7.0 } ?? false) ? 1 : 0
        }
    }

    static func standing(for family: BadgeFamily, _ inputs: AchievementInputs) -> BadgeStanding {
        let count = count(for: family.id, inputs)
        let earnedIndex = family.thresholds.lastIndex { count >= $0 }
        return BadgeStanding(family: family, count: count, earnedIndex: earnedIndex)
    }

    static func standings(_ inputs: AchievementInputs) -> [BadgeStanding] {
        BadgeCatalog.families.map { standing(for: $0, inputs) }
    }

    /// The community score: every tier earned across every family.
    static func totalPoints(_ inputs: AchievementInputs) -> Int {
        standings(inputs).reduce(0) { $0 + $1.points }
    }

    /// How many tiers (individual seals) have been earned in total.
    static func earnedTierCount(_ inputs: AchievementInputs) -> Int {
        standings(inputs).reduce(0) { $0 + (($1.earnedIndex.map { $0 + 1 }) ?? 0) }
    }
}
