import Foundation

/// What a free-typed phrase like "45g paste și 4 unități" resolves to: up to
/// one glucose value, one carb amount (with the food words that came with it)
/// and one insulin dose, ready to be logged as separate entries.
struct QuickPhrase: Equatable, Sendable {
    var glucoseMgdL: Double?
    var carbGrams: Double?
    var foodDescription: String?
    var insulinUnits: Double?

    var isEmpty: Bool { glucoseMgdL == nil && carbGrams == nil && insulinUnits == nil }
}

/// Turns one typed sentence into journal entries — on device, no network, no
/// model. The vocabulary covers Romanian and English because that's what the
/// app ships in the user's hands; unknown words are simply left to be the food
/// description.
///
/// Deliberately conservative: a bare number with no unit and no keyword nearby
/// is only accepted as glucose when it's the ONLY number in the phrase and
/// falls in a plausible glucose range — anything more clever guesses, and a
/// wrong guess in a medical journal is worse than asking the user to type "mg".
enum QuickPhraseParser {

    private static let carbUnits: Set<String> = ["g", "gr", "grame", "grams", "carb", "carbs", "carbo", "carbohidrati", "cho"]
    private static let insulinUnits: Set<String> = ["u", "ui", "un", "unitati", "unitate", "units", "unit"]
    private static let glucoseUnits: Set<String> = ["mg", "mg/dl", "mgdl", "mmol", "mmol/l", "mmoll"]
    private static let glucoseKeywords: Set<String> = ["glicemie", "glicemia", "glucoza", "glucose", "bg", "zahar"]
    /// Words that name things but are not food (connectors, verbs, keywords).
    private static let noise: Set<String> = ["si", "and", "cu", "with", "de", "la", "am", "mancat", "luat", "facut", "i", "ate", "had", "took", "for", "insulina", "insulin", "bolus"]

    static func parse(_ text: String, unit: GlucoseUnit) -> QuickPhrase {
        var phrase = QuickPhrase()
        let folded = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: ",", with: ".")

        // Tokens: numbers and words, in order.
        let tokens = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "/" })
            .map(String.init)
        var foodWords: [String] = []
        var bareNumbers: [Double] = []

        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            // A number possibly glued to its unit ("45g", "4u", "6.2mmol").
            let (numberPart, glued) = splitNumber(token)
            if let value = numberPart {
                let unitWord = glued ?? (index + 1 < tokens.count ? tokens[index + 1] : nil)
                let before = index > 0 ? tokens[index - 1] : nil
                let consumedNext = glued == nil && unitWord != nil

                if let unitWord, carbUnits.contains(unitWord) {
                    phrase.carbGrams = value
                    if consumedNext { index += 1 }
                } else if let unitWord, insulinUnits.contains(unitWord) {
                    phrase.insulinUnits = value
                    if consumedNext { index += 1 }
                } else if let unitWord, glucoseUnits.contains(unitWord) {
                    phrase.glucoseMgdL = normalizeGlucose(value, explicitMmol: unitWord.hasPrefix("mmol"), unit: unit)
                    if consumedNext { index += 1 }
                } else if let before, glucoseKeywords.contains(before) {
                    phrase.glucoseMgdL = normalizeGlucose(value, explicitMmol: false, unit: unit)
                } else {
                    bareNumbers.append(value)
                }
            } else if !noise.contains(token), !glucoseKeywords.contains(token),
                      !carbUnits.contains(token), !insulinUnits.contains(token),
                      !glucoseUnits.contains(token) {
                foodWords.append(token)
            }
            index += 1
        }

        // A single unclaimed number in glucose territory reads as the glucose —
        // but only in a phrase with no other words: "125" is a reading, while
        // the 2 in "2 ouă" is a count of eggs, not 36 mg/dL.
        if phrase.glucoseMgdL == nil, bareNumbers.count == 1, foodWords.isEmpty,
           phrase.isEmpty || bareNumbers[0] >= 40 {
            let value = bareNumbers[0]
            if unit == .mmolL, value >= 2, value <= 30 {
                phrase.glucoseMgdL = value * GlucoseUnit.conversionFactor
            } else if value >= 40, value <= 400 {
                phrase.glucoseMgdL = value
            }
        }

        if phrase.carbGrams != nil, !foodWords.isEmpty {
            // Original casing is nicer in the journal than the folded tokens.
            let originals = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { word in
                    let key = word.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                    return foodWords.contains(key)
                }
            phrase.foodDescription = (originals.isEmpty ? foodWords : originals).joined(separator: " ")
        }
        return phrase
    }

    /// Splits "45g" into (45, "g"); a plain "45" gives (45, nil); a word gives
    /// (nil, nil).
    private static func splitNumber(_ token: String) -> (Double?, String?) {
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return (nil, nil) }
        let rest = String(token.dropFirst(digits.count))
        return (value, rest.isEmpty ? nil : rest)
    }

    /// mmol → mg/dL when stated or when the user's display unit says so and the
    /// magnitude clearly can't be mg/dL.
    private static func normalizeGlucose(_ value: Double, explicitMmol: Bool, unit: GlucoseUnit) -> Double {
        if explicitMmol || (unit == .mmolL && value <= 30) {
            return value * GlucoseUnit.conversionFactor
        }
        return value
    }
}
