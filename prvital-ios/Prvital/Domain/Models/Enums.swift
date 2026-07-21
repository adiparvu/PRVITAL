import Foundation
import SwiftUI

// MARK: - Unified data model — shared enumerations
//
// Every medical record, regardless of its origin (Dexcom, FreeStyle Libre,
// Apple Health, Apple Watch, manual entry), is stored using the same schema
// and the same closed vocabularies below. Raw values are stable strings so the
// enums survive CloudKit sync and JSON export unchanged.

/// The kind of medical record a row represents.
enum RecordType: String, Codable, CaseIterable, Sendable {
    case glucose
    case insulin
    case carbohydrate
    case activity
    case observation
}

/// A continuous glucose sensor model, with its wear time and warm-up period.
enum SensorKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dexcomG7 = "dexcom_g7"
    case dexcomG6 = "dexcom_g6"
    case freeStyleLibre3 = "freestyle_libre_3"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dexcomG7: return String(localized: "Dexcom G7")
        case .dexcomG6: return String(localized: "Dexcom G6")
        case .freeStyleLibre3: return String(localized: "FreeStyle Libre 3")
        case .other: return String(localized: "Other sensor")
        }
    }

    /// Total time the sensor is worn before it must be replaced.
    var lifetime: TimeInterval {
        switch self {
        case .dexcomG7: return 10.5 * 86_400
        case .dexcomG6: return 10 * 86_400
        case .freeStyleLibre3: return 14 * 86_400
        case .other: return 10 * 86_400
        }
    }

    /// Warm-up after insertion before readings appear.
    var warmup: TimeInterval {
        switch self {
        case .dexcomG7: return 30 * 60
        case .dexcomG6: return 2 * 3_600
        case .freeStyleLibre3: return 60 * 60
        case .other: return 60 * 60
        }
    }
}

/// Where a food's nutrition came from: the user's own entry, or a lookup in the
/// Open Food Facts database.
enum FoodSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case manual
    case openFoodFacts = "open_food_facts"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return String(localized: "Entered by hand")
        case .openFoodFacts: return String(localized: "Open Food Facts")
        }
    }

    var symbol: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .openFoodFacts: return "barcode.viewfinder"
        }
    }
}

/// Where a value came from. Drives provenance display and conflict priority.
enum DataSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case dexcom
    case freeStyleLibre
    case otherCGM
    case nightscout
    case bloodGlucoseMeter
    case appleHealth
    case appleWatch
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dexcom: return "Dexcom"
        case .freeStyleLibre: return "FreeStyle Libre"
        case .otherCGM: return "CGM sensor"
        case .nightscout: return "Nightscout"
        case .bloodGlucoseMeter: return "Glucose meter"
        case .appleHealth: return "Apple Health"
        case .appleWatch: return "Apple Watch"
        case .manual: return "Manual entry"
        }
    }

    var symbol: String {
        switch self {
        case .dexcom, .freeStyleLibre, .otherCGM: return "sensor.tag.radiowaves.forward"
        case .nightscout: return "cloud"
        case .bloodGlucoseMeter: return "cross.vial"
        case .appleHealth: return "heart.text.square"
        case .appleWatch: return "applewatch"
        case .manual: return "hand.tap"
        }
    }

    /// True for continuous-glucose-monitoring sources (including Nightscout,
    /// which relays CGM `sgv` data from a self-hosted server).
    var isCGM: Bool {
        switch self {
        case .dexcom, .freeStyleLibre, .otherCGM, .nightscout: return true
        default: return false
        }
    }

    /// True for sources configured through a dedicated screen (a site URL/token
    /// or an account login) rather than the generic Connect button.
    var isCredentialed: Bool {
        switch self {
        case .nightscout, .dexcom, .freeStyleLibre: return true
        default: return false
        }
    }
}

/// Glucose direction of change, as reported by CGM sensors.
enum GlucoseTrend: String, Codable, CaseIterable, Sendable {
    case risingFast = "rising_fast"
    case rising
    case stable
    case falling
    case fallingFast = "falling_fast"

    var symbol: String {
        switch self {
        case .risingFast: return "arrow.up"
        case .rising: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .falling: return "arrow.down.right"
        case .fallingFast: return "arrow.down"
        }
    }

    var label: String {
        switch self {
        case .risingFast: return String(localized: "Rising fast")
        case .rising: return String(localized: "Rising")
        case .stable: return String(localized: "Stable")
        case .falling: return String(localized: "Falling")
        case .fallingFast: return String(localized: "Falling fast")
        }
    }
}

/// How a glucose value was obtained.
enum GlucoseMeasurementType: String, Codable, CaseIterable, Sendable {
    case cgm
    case fingerstick
    case manual
    case laboratory
    case calibration

    var label: String {
        switch self {
        case .cgm: return "Sensor"
        case .fingerstick: return "Finger stick"
        case .manual: return "Manual"
        case .laboratory: return "Lab"
        case .calibration: return "Calibration"
        }
    }
}

/// The unit a glucose value is expressed in.
enum GlucoseUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    var id: String { rawValue }

    /// mg/dL per 1 mmol/L.
    static let conversionFactor = 18.01801801801802

    func fromMgdL(_ value: Double) -> Double {
        switch self {
        case .mgdL: return value
        case .mmolL: return value / Self.conversionFactor
        }
    }

    func toMgdL(_ value: Double) -> Double {
        switch self {
        case .mgdL: return value
        case .mmolL: return value * Self.conversionFactor
        }
    }

    /// Sensible number of decimals for display (mg/dL is integer, mmol/L 1 dp).
    var fractionDigits: Int { self == .mgdL ? 0 : 1 }

    /// A sensible initial unit for a region. mmol/L is standard across much of
    /// the world (UK, Ireland, Canada, Australia, NZ, the Nordics, the
    /// Netherlands, Russia, China…); most other regions report in mg/dL. Used
    /// only to seed onboarding — the user always confirms.
    static func localeDefault(regionCode: String? = Locale.current.region?.identifier) -> GlucoseUnit {
        let mmolRegions: Set<String> = [
            "GB", "IE", "CA", "AU", "NZ", "NL", "RU", "CN", "SE", "NO",
            "FI", "DK", "CH", "IS", "HK", "ZA", "MY", "SG", "UA", "CZ"
        ]
        guard let region = regionCode?.uppercased() else { return .mgdL }
        return mmolRegions.contains(region) ? .mmolL : .mgdL
    }
}

/// Classification of a glucose value against the user's target range.
/// Maps to the dashboard's green / yellow / orange / red indicator.
enum GlucoseZone: String, Codable, CaseIterable, Sendable {
    case veryLow
    case low
    case inRange
    case high
    case veryHigh

    var label: String {
        switch self {
        case .veryLow: return String(localized: "Very low")
        case .low: return String(localized: "Low")
        case .inRange: return String(localized: "In range")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very high")
        }
    }

    /// Whether the value counts as a hypo / hyper event for statistics.
    var isHypo: Bool { self == .veryLow || self == .low }
    var isHyper: Bool { self == .high || self == .veryHigh }
}

/// Insulin pharmacology class.
enum InsulinType: String, Codable, CaseIterable, Sendable {
    case rapidActing = "rapid"
    case longActing = "long"
    case intermediate
    case premixed

    var label: String {
        switch self {
        case .rapidActing: return String(localized: "Rapid-acting")
        case .longActing: return String(localized: "Long-acting (basal)")
        case .intermediate: return String(localized: "Intermediate")
        case .premixed: return String(localized: "Pre-mixed")
        }
    }

    /// Basal insulins are tracked separately from bolus in statistics.
    var isBasal: Bool { self == .longActing }
}

/// How the insulin was delivered.
enum InsulinDeliveryMethod: String, Codable, CaseIterable, Sendable {
    case pen
    case syringe
    case pump
    case inhaled

    var label: String { rawValue.capitalized }
}

/// Why a dose was taken.
enum InsulinDoseContext: String, Codable, CaseIterable, Sendable {
    case mealBolus = "meal"
    case correction
    case basal
    case other

    var label: String {
        switch self {
        case .mealBolus: return String(localized: "Meal")
        case .correction: return String(localized: "Correction")
        case .basal: return String(localized: "Basal")
        case .other: return String(localized: "Other")
        }
    }
}

/// Meal category for carbohydrate entries.
enum MealType: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast
    case morningSnack = "morning_snack"
    case lunch
    case dinner
    case eveningSnack = "evening_snack"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return String(localized: "Breakfast")
        case .morningSnack: return String(localized: "Snack")
        case .lunch: return String(localized: "Lunch")
        case .dinner: return String(localized: "Dinner")
        case .eveningSnack: return String(localized: "Evening snack")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .morningSnack, .eveningSnack: return "cup.and.saucer"
        case .lunch: return "sun.max"
        case .dinner: return "sunset"
        }
    }
}

/// Physical-activity category.
enum ActivityType: String, Codable, CaseIterable, Sendable, Identifiable {
    case walking
    case running
    case gym
    case cycling
    case swimming
    case physicalWork = "physical_work"
    case rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .walking: return String(localized: "Walking")
        case .running: return String(localized: "Running")
        case .gym: return String(localized: "Gym")
        case .cycling: return String(localized: "Cycling")
        case .swimming: return String(localized: "Swimming")
        case .physicalWork: return String(localized: "Physical work")
        case .rest: return String(localized: "Rest")
        }
    }

    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .gym: return "dumbbell"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .physicalWork: return "hammer"
        case .rest: return "bed.double"
        }
    }
}

/// Relative exertion for an activity.
enum ActivityIntensity: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high

    var label: String { rawValue.capitalized }
}

/// A contextual note the user can attach to a day / entry.
enum ObservationTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case illness
    case stress
    case lackOfSleep = "lack_of_sleep"
    case dehydration
    case fever
    case menstruation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .illness: return String(localized: "Illness")
        case .stress: return String(localized: "Stress")
        case .lackOfSleep: return String(localized: "Lack of sleep")
        case .dehydration: return String(localized: "Dehydration")
        case .fever: return String(localized: "Fever")
        case .menstruation: return String(localized: "Menstruation")
        case .other: return String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .illness: return "cross.case"
        case .stress: return "bolt.heart"
        case .lackOfSleep: return "moon.zzz"
        case .dehydration: return "drop"
        case .fever: return "thermometer.high"
        case .menstruation: return "calendar.badge.clock"
        case .other: return "note.text"
        }
    }
}

// MARK: - Profile

/// The kind of diabetes (or related status) the person manages. Personalises
/// education and copy, and appears on the profile. Stored as a raw string so it
/// is CloudKit-safe.
enum DiabetesType: String, Codable, CaseIterable, Sendable, Identifiable {
    case type1 = "type_1"
    case type2 = "type_2"
    case lada
    case mody
    case gestational
    case prediabetes
    case caregiver
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .type1: return String(localized: "Type 1")
        case .type2: return String(localized: "Type 2")
        case .lada: return String(localized: "LADA")
        case .mody: return String(localized: "MODY")
        case .gestational: return String(localized: "Gestational")
        case .prediabetes: return String(localized: "Prediabetes")
        case .caregiver: return String(localized: "Caregiver")
        case .other: return String(localized: "Other")
        }
    }

    /// A one-line description shown under the picker.
    var detail: String {
        switch self {
        case .type1: return String(localized: "Autoimmune — the body makes little or no insulin.")
        case .type2: return String(localized: "The body doesn't use insulin well, and may not make enough.")
        case .lada: return String(localized: "Latent autoimmune diabetes in adults.")
        case .mody: return String(localized: "A rare inherited form of diabetes.")
        case .gestational: return String(localized: "Diabetes that develops during pregnancy.")
        case .prediabetes: return String(localized: "Higher-than-normal glucose, not yet type 2.")
        case .caregiver: return String(localized: "You're managing diabetes for someone you care for.")
        case .other: return String(localized: "Another form, or you'd rather not say.")
        }
    }
}

/// How the person manages therapy day to day. Shown on the profile and used to
/// tailor guidance. CloudKit-safe raw string.
enum TherapyApproach: String, Codable, CaseIterable, Sendable, Identifiable {
    case mdi
    case pump
    case basalOnly = "basal_only"
    case lifestyle
    case notOnInsulin = "not_on_insulin"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mdi: return String(localized: "Injections (MDI)")
        case .pump: return String(localized: "Insulin pump")
        case .basalOnly: return String(localized: "Basal only")
        case .lifestyle: return String(localized: "Diet & exercise")
        case .notOnInsulin: return String(localized: "Not on insulin")
        case .other: return String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .mdi: return "syringe"
        case .pump: return "cross.case.fill"
        case .basalOnly: return "moon.circle"
        case .lifestyle: return "figure.run"
        case .notOnInsulin: return "pills"
        case .other: return "ellipsis.circle"
        }
    }
}
