import Foundation

/// A trend value from Dexcom Share, which returns either a numeric code (older
/// API) or a name string (newer API).
enum DexcomTrendValue: Decodable, Equatable, Sendable {
    case code(Int)
    case name(String)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .code(value)
        } else if let value = try? container.decode(String.self) {
            self = .name(value)
        } else {
            self = .unknown
        }
    }
}

/// One glucose value from the Dexcom Share `ReadPublisherLatestGlucoseValues`
/// response. `WT` is a `/Date(…)/` epoch-millisecond string; `Value` is mg/dL.
struct DexcomShareEntry: Decodable, Sendable {
    let value: Double
    let wt: String
    let trend: DexcomTrendValue

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case wt = "WT"
        case trend = "Trend"
    }
}

/// Pure decoding helpers for the Dexcom Share format — timestamp and trend
/// parsing and sample construction, all deterministic and unit-tested.
enum DexcomShareParsing {

    /// Parses a `/Date(1699999999000)/` or `/Date(1699999999000-0800)/` string
    /// into a `Date`. The milliseconds are an absolute UTC instant; any trailing
    /// offset is only a display hint and is ignored.
    static func parseWT(_ string: String) -> Date? {
        guard let start = string.range(of: "Date(")?.upperBound else { return nil }
        let rest = string[start...]
        var digits = ""
        for character in rest {
            if character.isNumber { digits.append(character) }
            else { break }   // stop at ')' or a +/- offset
        }
        guard let millis = Double(digits), millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    /// Maps a Dexcom trend (code 1–7 or a name) to the app's five levels.
    static func trend(_ value: DexcomTrendValue) -> GlucoseTrend? {
        switch value {
        case .code(let code):
            switch code {
            case 1: return .risingFast    // DoubleUp
            case 2: return .rising        // SingleUp
            case 3: return .rising        // FortyFiveUp
            case 4: return .stable        // Flat
            case 5: return .falling       // FortyFiveDown
            case 6: return .falling       // SingleDown
            case 7: return .fallingFast   // DoubleDown
            default: return nil           // NotComputable / RateOutOfRange
            }
        case .name(let name):
            switch name {
            case "DoubleUp": return .risingFast
            case "SingleUp", "FortyFiveUp": return .rising
            case "Flat": return .stable
            case "FortyFiveDown", "SingleDown": return .falling
            case "DoubleDown": return .fallingFast
            default: return nil
            }
        case .unknown:
            return nil
        }
    }

    static func sample(from entry: DexcomShareEntry) -> NormalizedGlucoseSample? {
        guard entry.value > 0, let timestamp = parseWT(entry.wt) else { return nil }
        return NormalizedGlucoseSample(
            id: "dexcom-\(Int(timestamp.timeIntervalSince1970))",
            valueMgdL: entry.value,
            timestamp: timestamp,
            source: .dexcom,
            trend: trend(entry.trend),
            measurementType: .cgm
        )
    }
}

/// A `Sendable` HTTP client for the unofficial **Dexcom Share** service (the same
/// endpoint the Dexcom Follow app uses). It authenticates with the user's Dexcom
/// account and reads the latest sensor values. Region-aware: US vs. outside-US
/// share servers. No official SDK is involved.
struct DexcomShareClient: Sendable {
    let credentials: SourceCredentials

    /// The Dexcom Share application identifier (a fixed public constant).
    static let applicationID = "d89443d2-327c-4a6f-89e5-496bbb0317db"

    private var baseURL: URL {
        credentials.region.lowercased() == "ous"
            ? URL(string: "https://shareous1.dexcom.com")!
            : URL(string: "https://share2.dexcom.com")!
    }

    func fetchSamples(minutes: Int, maxCount: Int) async throws -> [NormalizedGlucoseSample] {
        let sessionID = try await authenticate()
        let entries = try await readLatest(sessionID: sessionID, minutes: minutes, maxCount: maxCount)
        return entries.compactMap(DexcomShareParsing.sample(from:))
    }

    /// Two-step Share login: authenticate the account, then open a session.
    func authenticate() async throws -> String {
        let accountID = try await postForString(
            path: "ShareWebServices/Services/General/AuthenticatePublisherAccount",
            body: ["accountName": credentials.username,
                   "password": credentials.password,
                   "applicationId": Self.applicationID])
        try Self.requireValidUUID(accountID)

        let sessionID = try await postForString(
            path: "ShareWebServices/Services/General/LoginPublisherAccountById",
            body: ["accountId": accountID,
                   "password": credentials.password,
                   "applicationId": Self.applicationID])
        try Self.requireValidUUID(sessionID)
        return sessionID
    }

    private func readLatest(sessionID: String, minutes: Int, maxCount: Int) async throws -> [DexcomShareEntry] {
        let path = "ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues"
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SourceError.underlying("Invalid Dexcom Share URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "minutes", value: String(max(1, minutes))),
            URLQueryItem(name: "maxCount", value: String(max(1, maxCount))),
        ]
        guard let url = components.url else { throw SourceError.underlying("Invalid Dexcom Share URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode([DexcomShareEntry].self, from: data)
    }

    private func postForString(path: String, body: [String: String]) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(String.self, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.underlying("No response from Dexcom Share.")
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403, 500:
            // Dexcom returns a 500 SSO fault for bad credentials.
            throw SourceError.notAuthorized
        default:
            throw SourceError.underlying("Dexcom Share returned HTTP \(http.statusCode).")
        }
    }

    private static func requireValidUUID(_ value: String) throws {
        let empty = "00000000-0000-0000-0000-000000000000"
        guard !value.isEmpty, value != empty else { throw SourceError.notAuthorized }
    }
}
