import Foundation
import SwiftData

/// The person using Prvital — their name and clinical context.
///
/// Prvital has no server and no login: a "profile" is simply a local record of
/// who this is and how they manage diabetes. It personalises the app and is the
/// identity attached when sharing with a partner or caregiver. It follows the
/// user across their own devices when iCloud sync is on.
///
/// CloudKit-safe by construction: every stored property has a default, optionals
/// stand in for absent values, enums are stored as raw strings, and there are no
/// unique constraints.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    /// An SF Symbol used as the avatar when no name initial is shown.
    var avatarSymbol: String = "person.crop.circle.fill"
    var diabetesTypeRaw: String = DiabetesType.type1.rawValue
    var therapyRaw: String = TherapyApproach.mdi.rawValue
    /// Year of diagnosis, if the user chooses to record it.
    var diagnosisYear: Int?
    /// A free-text note (care team, clinic, anything the user wants on hand).
    var careTeamNote: String?
    /// The avatar tint as a 6-digit "RRGGBB" hex string (e.g. "8B6FE8").
    /// `nil` means "follow the app accent colour". Doubles as the ring colour
    /// around a photo avatar.
    var avatarColorHex: String?
    /// An optional profile photo (downscaled JPEG data). When present it takes
    /// the place of the initials/symbol avatar. Kept small so it's CloudKit- and
    /// widget-friendly.
    var avatarImageData: Data?
    /// Year of birth, if the user chooses to record it.
    var birthYear: Int?
    /// Body weight in kilograms — the user's own record only, never used for dosing.
    var weightKg: Double?
    /// Height in centimetres — the user's own record only, never used for dosing.
    var heightCm: Double?
    /// Name of the basal (long-acting) insulin in use. Free text, purely a label.
    var basalInsulinName: String?
    /// Name of the bolus (mealtime) insulin in use. Free text, purely a label.
    var bolusInsulinName: String?
    /// The CGM / sensor model worn (e.g. "Dexcom G7"). Free text.
    var cgmModel: String?
    /// The blood-glucose meter model used. Free text.
    var meterModel: String?
    /// The insulin pump model — relevant when therapy is a pump. Free text.
    var pumpModel: String?
    /// The treating doctor or clinic, as the user wants it written.
    var doctorName: String?
    /// The care team's phone number, as typed; sanitised only when dialling.
    var doctorPhone: String?
    /// The next scheduled appointment, if the user chooses to track it.
    var nextAppointment: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var diabetesType: DiabetesType {
        get { DiabetesType(rawValue: diabetesTypeRaw) ?? .type1 }
        set { diabetesTypeRaw = newValue.rawValue }
    }
    var therapy: TherapyApproach {
        get { TherapyApproach(rawValue: therapyRaw) ?? .mdi }
        set { therapyRaw = newValue.rawValue }
    }

    /// Uppercased initials for the avatar, or nil when there's no usable name.
    var initials: String? { ProfileFormatting.initials(from: displayName) }

    /// A short, share-friendly one-liner, e.g. "Type 1 · Injections (MDI)".
    var summaryLine: String {
        "\(diabetesType.displayName) · \(therapy.displayName)"
    }

    /// The avatar tint parsed to an RGB value, or nil when unset/invalid
    /// (meaning "use the app accent").
    var avatarColorValue: UInt? { ProfileFormatting.hexColorValue(avatarColorHex) }

    /// Whole years since diagnosis, or nil when no diagnosis year is set.
    var yearsWithDiabetes: Int? { ProfileFormatting.yearsSince(diagnosisYear) }

    init(
        id: UUID = UUID(),
        displayName: String = "",
        avatarSymbol: String = "person.crop.circle.fill",
        diabetesType: DiabetesType = .type1,
        therapy: TherapyApproach = .mdi,
        diagnosisYear: Int? = nil,
        careTeamNote: String? = nil,
        avatarColorHex: String? = nil,
        birthYear: Int? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        basalInsulinName: String? = nil,
        bolusInsulinName: String? = nil,
        cgmModel: String? = nil,
        meterModel: String? = nil,
        pumpModel: String? = nil,
        doctorName: String? = nil,
        doctorPhone: String? = nil,
        nextAppointment: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.diabetesTypeRaw = diabetesType.rawValue
        self.therapyRaw = therapy.rawValue
        self.diagnosisYear = diagnosisYear
        self.careTeamNote = careTeamNote
        self.avatarColorHex = avatarColorHex
        self.birthYear = birthYear
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.basalInsulinName = basalInsulinName
        self.bolusInsulinName = bolusInsulinName
        self.cgmModel = cgmModel
        self.meterModel = meterModel
        self.pumpModel = pumpModel
        self.doctorName = doctorName
        self.doctorPhone = doctorPhone
        self.nextAppointment = nextAppointment
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Pure, testable formatting for a profile — kept out of the `@Model` so it can
/// be unit-tested without a SwiftData container.
enum ProfileFormatting {
    /// Up to two uppercased initials from a display name, or nil when the name has
    /// no letters. "Ada Lovelace" → "AL", "madonna" → "M", "  " → nil.
    static func initials(from name: String) -> String? {
        let words = name
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .compactMap { $0.first(where: \.isLetter) }
        guard let first = words.first else { return nil }
        let letters = words.count >= 2 ? [first, words[1]] : [first]
        return String(letters).uppercased()
    }

    /// Parses a 6-digit "RRGGBB" hex string (an optional leading "#" is fine)
    /// into an RGB value. Anything else — nil, empty, wrong length, non-hex —
    /// returns nil, which callers treat as "use the app accent".
    static func hexColorValue(_ hex: String?) -> UInt? {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt(text, radix: 16) else { return nil }
        return value
    }

    /// Whole years elapsed since `year`, clamped to zero (a year typed in the
    /// future counts as "this year"), or nil when no year is recorded.
    static func yearsSince(
        _ year: Int?,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> Int? {
        guard let year else { return nil }
        return max(0, currentYear - year)
    }

    /// The header's duration phrase for a diagnosis, e.g. "7 years with diabetes".
    /// Localized so it never shows English on a translated device.
    static func durationLine(yearsWithDiabetes years: Int) -> String {
        switch years {
        case ..<1: return String(localized: "Diagnosed this year")
        case 1: return String(localized: "1 year with diabetes")
        default: return String(localized: "\(years) years with diabetes")
        }
    }

    /// A user-typed measurement ("72", "72.5", "72,5") as a positive number, or
    /// nil when empty or implausible. Comma decimals are accepted because many
    /// keyboards produce them.
    static func measurement(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value < 1000 else { return nil }
        return value
    }

    /// A measurement rendered back for its text field: whole numbers without a
    /// decimal ("72"), otherwise one decimal place ("72.5"); "" when unset.
    static func measurementText(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    /// A `tel:` URL from a user-typed phone number, or nil when no digits
    /// remain. Keeps digits and a single leading "+" so "+40 (721) 555-123"
    /// becomes "tel:+40721555123". Mirrors the emergency card's sanitiser.
    static func telURL(from phone: String) -> URL? {
        let raw = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = raw.filter(\.isWholeNumber)
        guard !digits.isEmpty else { return nil }
        let number = raw.hasPrefix("+") ? "+" + digits : digits
        return URL(string: "tel:\(number)")
    }

    /// Whole calendar days from `reference` to `date` (start-of-day to
    /// start-of-day, so "tomorrow" is 1 regardless of the time of day).
    static func daysUntil(
        _ date: Date,
        from reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: reference)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    /// The countdown line for an upcoming appointment, shown only when it's
    /// today through 30 days away — nil for past dates or the further future.
    static func appointmentCountdown(daysAway: Int) -> String? {
        switch daysAway {
        case 0: return String(localized: "Appointment today")
        case 1: return String(localized: "Appointment tomorrow")
        case 2...30: return String(localized: "Appointment in \(daysAway) days")
        default: return nil
        }
    }
}
