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

    init(
        id: UUID = UUID(),
        displayName: String = "",
        avatarSymbol: String = "person.crop.circle.fill",
        diabetesType: DiabetesType = .type1,
        therapy: TherapyApproach = .mdi,
        diagnosisYear: Int? = nil,
        careTeamNote: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.diabetesTypeRaw = diabetesType.rawValue
        self.therapyRaw = therapy.rawValue
        self.diagnosisYear = diagnosisYear
        self.careTeamNote = careTeamNote
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
}
