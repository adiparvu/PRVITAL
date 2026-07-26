import Foundation

/// Turns a transcribed utterance ("60 de grame, pizza", "6 units", "glicemie
/// 120") into loggable entries. Pure text → values, no Speech dependency, so
/// the whole grammar is unit-testable without a microphone.
///
/// The parser is deliberately conservative: a number is only accepted when a
/// recognisable unit word sits next to it. A bare "60" logs nothing — for
/// medical entries a wrong guess is worse than asking the user to say the unit.
enum VoiceEntryParser {

    /// Everything recognised in one utterance. An utterance may carry several
    /// entries at once ("60 de grame și 6 unități").
    struct Result: Equatable {
        var carbsGrams: Double?
        /// Leftover free text ("pizza"), attached only when carbs were spoken —
        /// it becomes the meal's food description.
        var foodDescription: String?
        var insulinUnits: Double?
        /// The glucose number exactly as spoken; interpret it with
        /// `glucoseMgdL(fromSpoken:preferred:)`.
        var spokenGlucose: Double?

        var isEmpty: Bool {
            carbsGrams == nil && insulinUnits == nil && spokenGlucose == nil
        }
    }

    private enum Category {
        case carbs, insulin, glucose
    }

    /// Filler words that may sit between a number and its unit ("60 *de* grame",
    /// "7 units *of* insulin") or between a keyword and its number.
    private static let fillers: Set<String> = [
        "de", "of", "din", "cu", "with", "la", "si", "and", "mai", "en", "von", "di", "y", "et"
    ]

    /// Keyword prefixes, matched against diacritic-folded lowercase tokens, so
    /// "unități", "unitati" and "units" all resolve the same way. The lists
    /// cover every language the app ships in — the recogniser transcribes in
    /// the user's language, so the grammar has to speak it too.
    private static let carbsPrefixes = [
        "gram", "грамм",                               // grams in all Latin-script languages + ru
        "carb", "glucid", "kohlenhydrat", "koolhydra", // carbs: en/it/pt+es, ro/fr, de, nl
        "hidrato", "weglowodan", "углевод"             // es, pl, ru
    ]
    private static let insulinPrefixes = [
        "unit", "unidad", "eenhe", "jednost", "einheit", // units: en/ro/fr/it, es/pt, nl, pl, de
        "insulin", "инсулин", "единиц"                   // insulin everywhere + ru units
    ]
    private static let glucosePrefixes = [
        "glicemi", "glucoz", "glucos", "glicos", "glukos", "glykemi", "glikemi", // glucose/glycemia variants
        "zahar", "sugar", "zucker", "blutzucker", "cukier", "cukr",              // "sugar" in ro/en/de/pl/cz
        "глюкоз", "гликеми", "сахар"                                             // ru
    ]
    private static let carbsExact: Set<String> = ["g", "gr"]
    private static let insulinExact: Set<String> = ["u", "ui", "iu"]
    private static let glucoseExact: Set<String> = ["mg", "mmol", "mgdl"]

    static func parse(_ utterance: String) -> Result {
        // Keep two parallel token lists: folded for matching, original for the
        // food description, so "Pizza Margherita" keeps its casing.
        let originalTokens = tokenize(utterance)
        let foldedTokens = originalTokens.map { fold($0) }

        var result = Result()
        var consumed = [Bool](repeating: false, count: foldedTokens.count)

        for index in foldedTokens.indices {
            guard !consumed[index], let number = number(from: foldedTokens[index]) else { continue }

            // Look ahead (skipping fillers) for the unit word: "60 de grame".
            var match: (category: Category, keywordIndex: Int)?
            var ahead = index + 1
            var skipped = 0
            while ahead < foldedTokens.count, skipped < 3, match == nil {
                let token = foldedTokens[ahead]
                if let category = category(of: token) {
                    match = (category, ahead)
                } else if fillers.contains(token) {
                    skipped += 1
                    ahead += 1
                } else {
                    break
                }
            }

            // Otherwise look behind: "glicemie 120", "insulină 4".
            if match == nil {
                var behind = index - 1
                skipped = 0
                while behind >= 0, skipped < 3 {
                    let token = foldedTokens[behind]
                    if consumed[behind] { break }
                    if let category = category(of: token) {
                        match = (category, behind)
                        break
                    } else if fillers.contains(token) {
                        skipped += 1
                        behind -= 1
                    } else {
                        break
                    }
                }
            }

            guard let match else { continue }
            consumed[index] = true
            consumed[match.keywordIndex] = true
            switch match.category {
            case .carbs: if result.carbsGrams == nil { result.carbsGrams = number }
            case .insulin: if result.insulinUnits == nil { result.insulinUnits = number }
            case .glucose: if result.spokenGlucose == nil { result.spokenGlucose = number }
            }
        }

        // Whatever was neither a number, a unit word nor a filler is free text —
        // meaningful only as the food description of a carb entry.
        if result.carbsGrams != nil {
            let words = originalTokens.indices.filter { index in
                let token = foldedTokens[index]
                return !consumed[index]
                    && number(from: token) == nil
                    && category(of: token) == nil
                    && !fillers.contains(token)
            }.map { originalTokens[$0] }
            if !words.isEmpty {
                let text = words.joined(separator: " ")
                result.foodDescription = text.prefix(1).uppercased() + text.dropFirst()
            }
        }

        return result
    }

    /// Interprets a spoken glucose number as mg/dL. People read the number off
    /// their meter without naming the unit, so the scale itself disambiguates:
    /// no live glucose is under 30 mg/dL, and none reaches 30 mmol/L outside an
    /// emergency — a small value is therefore mmol/L, a large one mg/dL. The
    /// preferred unit only widens its own side of the boundary.
    static func glucoseMgdL(fromSpoken value: Double, preferred: GlucoseUnit) -> Double {
        let mmolBoundary: Double = preferred == .mmolL ? 35 : 30
        if value < mmolBoundary {
            return GlucoseUnit.mmolL.toMgdL(value)
        }
        return value
    }

    // MARK: Tokenising

    private static func tokenize(_ utterance: String) -> [String] {
        // "7,5" is a decimal in every language the app speaks — join it before
        // splitting on punctuation.
        var text = utterance
        while let range = text.range(of: #"(?<=\d),(?=\d)"#, options: .regularExpression) {
            text = text.replacingCharacters(in: range, with: ".")
        }
        return text.split(whereSeparator: { character in
            !(character.isLetter || character.isNumber || character == ".")
        }).map { token in
            // Strip sentence-final dots so "grame." matches, without touching "7.5".
            var trimmed = String(token)
            while trimmed.hasSuffix("."), Double(trimmed) == nil {
                trimmed.removeLast()
            }
            return trimmed
        }.filter { !$0.isEmpty }
    }

    private static func fold(_ token: String) -> String {
        token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func number(from token: String) -> Double? {
        guard token.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(token)
    }

    private static func category(of token: String) -> Category? {
        if carbsExact.contains(token) || carbsPrefixes.contains(where: { token.hasPrefix($0) }) { return .carbs }
        if insulinExact.contains(token) || insulinPrefixes.contains(where: { token.hasPrefix($0) }) { return .insulin }
        if glucoseExact.contains(token) || glucosePrefixes.contains(where: { token.hasPrefix($0) }) { return .glucose }
        return nil
    }
}
