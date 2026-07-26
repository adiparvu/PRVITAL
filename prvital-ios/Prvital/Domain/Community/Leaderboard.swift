import Foundation

/// The user's community-leaderboard choice. Off by default; when on, ONLY the
/// pseudonym, badge points, badge-level count and the chosen country ever leave
/// the device — never a glucose value or any medical datum.
struct CommunityPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var handle = ""
    /// ISO 3166-1 alpha-2, uppercased ("RO"). Defaults to the device region.
    var countryCode = ""

    static let `default` = CommunityPreferences()
}

/// One row of the leaderboard, already resolved for display.
struct LeaderboardEntry: Identifiable, Equatable, Sendable {
    let id: String
    let handle: String
    let points: Int
    let badges: Int
    let country: String
    let continentRaw: String
    let isMe: Bool
}

/// The three boards.
enum LeaderboardScope: String, CaseIterable, Identifiable, Sendable {
    case country, continent, global
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .country: String(localized: "Country")
        case .continent: String(localized: "Continent")
        case .global: String(localized: "Global")
        }
    }
}

/// ISO country → continent bucket, so the continent board needs no lookup
/// service. Raw continent codes are stored on the record ("EU", "AS", …).
enum WorldContinents {
    private static let europe: Set<String> = [
        "AD", "AL", "AT", "AX", "BA", "BE", "BG", "BY", "CH", "CZ", "DE", "DK", "EE", "ES",
        "FI", "FO", "FR", "GB", "GG", "GI", "GR", "HR", "HU", "IE", "IM", "IS", "IT", "JE",
        "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "MT", "NL", "NO", "PL", "PT", "RO",
        "RS", "RU", "SE", "SI", "SJ", "SK", "SM", "UA", "VA", "XK",
    ]
    private static let asia: Set<String> = [
        "AE", "AF", "AM", "AZ", "BD", "BH", "BN", "BT", "CN", "CY", "GE", "HK", "ID", "IL",
        "IN", "IQ", "IR", "JO", "JP", "KG", "KH", "KP", "KR", "KW", "KZ", "LA", "LB", "LK",
        "MM", "MN", "MO", "MV", "MY", "NP", "OM", "PH", "PK", "PS", "QA", "SA", "SG", "SY",
        "TH", "TJ", "TL", "TM", "TR", "TW", "UZ", "VN", "YE",
    ]
    private static let africa: Set<String> = [
        "AO", "BF", "BI", "BJ", "BW", "CD", "CF", "CG", "CI", "CM", "CV", "DJ", "DZ", "EG",
        "EH", "ER", "ET", "GA", "GH", "GM", "GN", "GQ", "GW", "KE", "KM", "LR", "LS", "LY",
        "MA", "MG", "ML", "MR", "MU", "MW", "MZ", "NA", "NE", "NG", "RE", "RW", "SC", "SD",
        "SH", "SL", "SN", "SO", "SS", "ST", "SZ", "TD", "TG", "TN", "TZ", "UG", "YT", "ZA",
        "ZM", "ZW",
    ]
    private static let northAmerica: Set<String> = [
        "AG", "AI", "AW", "BB", "BL", "BM", "BQ", "BS", "BZ", "CA", "CR", "CU", "CW", "DM",
        "DO", "GD", "GL", "GP", "GT", "HN", "HT", "JM", "KN", "KY", "LC", "MF", "MQ", "MS",
        "MX", "NI", "PA", "PM", "PR", "SV", "SX", "TC", "TT", "US", "VC", "VG", "VI",
    ]
    private static let southAmerica: Set<String> = [
        "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PE", "PY", "SR", "UY", "VE",
    ]
    private static let oceania: Set<String> = [
        "AS", "AU", "CK", "FJ", "FM", "GU", "KI", "MH", "MP", "NC", "NF", "NR", "NU", "NZ",
        "PF", "PG", "PW", "SB", "TK", "TO", "TV", "VU", "WF", "WS",
    ]

    /// The continent bucket for an ISO alpha-2 country code; nil when unknown.
    static func continent(forCountry code: String) -> String? {
        let c = code.uppercased()
        if europe.contains(c) { return "EU" }
        if asia.contains(c) { return "AS" }
        if africa.contains(c) { return "AF" }
        if northAmerica.contains(c) { return "NA" }
        if southAmerica.contains(c) { return "SA" }
        if oceania.contains(c) { return "OC" }
        if c == "AQ" { return "AN" }
        return nil
    }

    static func displayName(forContinent raw: String) -> String {
        switch raw {
        case "EU": String(localized: "Europe")
        case "AS": String(localized: "Asia")
        case "AF": String(localized: "Africa")
        case "NA": String(localized: "North America")
        case "SA": String(localized: "South America")
        case "OC": String(localized: "Oceania")
        case "AN": String(localized: "Antarctica")
        default: raw
        }
    }

    /// The regional-indicator flag for a country code ("RO" → 🇷🇴).
    static func flag(forCountry code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            guard scalar.value >= 65, scalar.value <= 90,
                  let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return }
            result.unicodeScalars.append(flagScalar)
        }
    }
}
