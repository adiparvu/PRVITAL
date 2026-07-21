import Foundation

/// A reference list of the insulins and devices people with diabetes commonly
/// use, current to 2026, so the profile's therapy fields can offer suggestions
/// as the user types. These are plain labels for the user's own records and
/// shared reports — Prvital never uses them to calculate or suggest doses, and
/// free text is always allowed for anything not listed.
enum TherapyCatalog {
    /// Which therapy field a picker is filling, with its list and titles.
    enum Field: String, CaseIterable, Identifiable {
        case basalInsulin
        case bolusInsulin
        case cgm
        case meter
        case pump

        var id: String { rawValue }

        var title: String {
            switch self {
            case .basalInsulin: String(localized: "Basal insulin")
            case .bolusInsulin: String(localized: "Bolus insulin")
            case .cgm: String(localized: "CGM / sensor")
            case .meter: String(localized: "Meter")
            case .pump: String(localized: "Pump")
            }
        }

        var searchPrompt: String {
            switch self {
            case .basalInsulin, .bolusInsulin: String(localized: "Search insulins")
            case .cgm: String(localized: "Search sensors")
            case .meter: String(localized: "Search meters")
            case .pump: String(localized: "Search pumps")
            }
        }

        var options: [String] {
            switch self {
            case .basalInsulin: TherapyCatalog.basalInsulins
            case .bolusInsulin: TherapyCatalog.bolusInsulins
            case .cgm: TherapyCatalog.cgmSensors
            case .meter: TherapyCatalog.meters
            case .pump: TherapyCatalog.pumps
            }
        }
    }

    /// Long-acting / basal insulins (brand — molecule), grouped by molecule.
    static let basalInsulins: [String] = [
        // Glargine
        "Lantus (glargine U100)",
        "Basaglar (glargine U100)",
        "Abasaglar (glargine U100)",
        "Semglee (glargine U100)",
        "Rezvoglar (glargine U100)",
        "Toujeo (glargine U300)",
        // Degludec
        "Tresiba (degludec U100)",
        "Tresiba (degludec U200)",
        // Detemir
        "Levemir (detemir)",
        // NPH / intermediate
        "Humulin N (NPH)",
        "Novolin N (NPH)",
        "Insulatard (NPH)",
        // Combo basal
        "Ryzodeg (degludec/aspart)",
    ]

    /// Rapid- and short-acting / bolus insulins.
    static let bolusInsulins: [String] = [
        // Aspart
        "NovoRapid (aspart)",
        "NovoLog (aspart)",
        "Fiasp (faster aspart)",
        "Trurapi (aspart)",
        "Kirsty (aspart)",
        // Lispro
        "Humalog (lispro)",
        "Admelog (lispro)",
        "Lyumjev (lispro-aabc)",
        // Glulisine
        "Apidra (glulisine)",
        // Regular / short
        "Humulin R (regular)",
        "Novolin R (regular)",
        "Actrapid (regular)",
        // Inhaled
        "Afrezza (inhaled)",
        // Premixed
        "NovoMix 30 (aspart mix)",
        "Humalog Mix25 (lispro mix)",
        "Humalog Mix50 (lispro mix)",
        "Humulin M3 (regular mix)",
    ]

    /// Continuous glucose monitors / sensors available around 2025–2026.
    static let cgmSensors: [String] = [
        "Dexcom G7",
        "Dexcom G6",
        "Dexcom ONE+",
        "Dexcom ONE",
        "Dexcom Stelo",
        "FreeStyle Libre 3 Plus",
        "FreeStyle Libre 3",
        "FreeStyle Libre 2 Plus",
        "FreeStyle Libre 2",
        "FreeStyle Libre Rio",
        "Medtronic Simplera Sync",
        "Medtronic Simplera",
        "Medtronic Guardian 4",
        "Eversense 365",
        "Eversense E3",
    ]

    /// Blood-glucose meters (fingerstick).
    static let meters: [String] = [
        "Accu-Chek Guide",
        "Accu-Chek Instant",
        "Accu-Chek Aviva",
        "Accu-Chek Mobile",
        "Contour Next One",
        "Contour Next",
        "Contour Plus One",
        "OneTouch Verio Reflect",
        "OneTouch Verio Flex",
        "OneTouch Ultra Plus Flex",
        "OneTouch Select Plus",
        "FreeStyle Optium Neo",
        "FreeStyle Freedom Lite",
        "TRUE Metrix",
        "CareSens N",
        "GlucoMen areo",
    ]

    /// Insulin pumps (relevant when therapy is a pump).
    static let pumps: [String] = [
        "Omnipod 5",
        "Omnipod DASH",
        "Tandem t:slim X2",
        "Tandem Mobi",
        "Medtronic MiniMed 780G",
        "Medtronic MiniMed 770G",
        "Ypsomed mylife YpsoPump",
        "Beta Bionics iLet",
        "Dana Diabecare RS",
        "Dana-i",
        "Accu-Chek Insight",
    ]

    /// Filters `options` for a query, ranking prefix matches (on the whole label
    /// or any word) above looser "contains" matches, and dropping non-matches.
    /// An empty query returns the list unchanged.
    static func filter(_ options: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return options }
        var prefix: [String] = []
        var contains: [String] = []
        for option in options {
            let lower = option.lowercased()
            if lower.hasPrefix(q) || lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
                prefix.append(option)
            } else if lower.contains(q) {
                contains.append(option)
            }
        }
        return prefix + contains
    }
}
