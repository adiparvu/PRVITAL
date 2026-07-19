import Foundation

/// A stateless HTTP client for a Nightscout site's REST API.
///
/// It is a `Sendable` value with no reference state, so it can run its `async`
/// requests off the main actor and hand back already-`Sendable`
/// `NormalizedGlucoseSample`s.
///
/// It queries the **type-filtered** `entries/sgv.json` route so the server
/// returns sensor (`sgv`) rows only — never the calibration/meter rows that the
/// mixed `entries.json` collection interleaves — and, when a lower bound is
/// given, adds a server-side `date` filter so a time window (not a fixed page
/// size) determines what comes back.
struct NightscoutClient: Sendable {
    let baseURL: URL
    let token: String

    /// Fetches sensor (`sgv`) entries newest-first. When `since` is provided the
    /// server returns every sgv entry at or after it (up to `count`); otherwise
    /// it returns the newest `count`.
    func fetchEntries(since: Date? = nil, count: Int) async throws -> [NormalizedGlucoseSample] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/entries/sgv.json"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SourceError.underlying("Invalid Nightscout URL.")
        }

        var queryItems = [URLQueryItem(name: "count", value: String(max(1, count)))]
        if let since {
            let millis = Int(since.timeIntervalSince1970 * 1000)
            queryItems.append(URLQueryItem(name: "find[date][$gte]", value: String(millis)))
        }
        if !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw SourceError.underlying("Invalid Nightscout URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SourceError.underlying("No response from Nightscout.")
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw SourceError.underlying("Nightscout rejected the token (HTTP \(http.statusCode)).")
        default:
            throw SourceError.underlying("Nightscout returned HTTP \(http.statusCode).")
        }

        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        return entries.compactMap { $0.asSample() }
    }
}

/// One raw entry from the Nightscout `entries` collection. Only sensor (`sgv`)
/// entries are turned into samples; calibration and meter rows are ignored here.
struct NightscoutEntry: Decodable, Sendable {
    let id: String?
    let sgv: Double?
    let date: Double?          // epoch milliseconds
    let dateString: String?
    let direction: String?
    let device: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case sgv, date, dateString, direction, device, type
    }

    func asSample() -> NormalizedGlucoseSample? {
        guard let sgv, sgv > 0 else { return nil }

        let timestamp: Date
        if let date {
            timestamp = Date(timeIntervalSince1970: date / 1000)
        } else if let dateString, let parsed = Self.parseISO(dateString) {
            timestamp = parsed
        } else {
            return nil
        }

        let identifier = id ?? "nightscout-\(Int(timestamp.timeIntervalSince1970))"
        return NormalizedGlucoseSample(
            id: identifier,
            valueMgdL: sgv,
            timestamp: timestamp,
            source: .nightscout,
            trend: Self.trend(from: direction),
            measurementType: .cgm,
            deviceID: device
        )
    }

    /// Parses a Nightscout `dateString`, tolerating both fractional-second
    /// (`...T12:00:00.000Z`) and whole-second ISO 8601 forms.
    static func parseISO(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    /// Maps Nightscout's `direction` string to the app's five trend levels.
    static func trend(from direction: String?) -> GlucoseTrend? {
        switch direction {
        case "DoubleUp": return .risingFast
        case "SingleUp", "FortyFiveUp": return .rising
        case "Flat": return .stable
        case "FortyFiveDown", "SingleDown": return .falling
        case "DoubleDown": return .fallingFast
        default: return nil   // NONE / NOT COMPUTABLE / RATE OUT OF RANGE
        }
    }
}

/// Nightscout as a glucose source: a real, user-configurable HTTP integration
/// (no vendor SDK required). It reads the current site + token from
/// `Preferences` each time, so changing the configuration takes effect on the
/// next sync without re-wiring anything.
@MainActor
final class NightscoutGlucoseSource: GlucoseSource {
    let source: DataSource = .nightscout
    private let preferences: Preferences
    private(set) var connectionState: SourceConnectionState

    init(preferences: Preferences) {
        self.preferences = preferences
        self.connectionState = preferences.nightscout.isConfigured ? .connected : .notConnected
    }

    /// A network source is always "available"; whether it syncs depends on
    /// configuration, surfaced through `connectionState`.
    var isAvailable: Bool { true }

    private var client: NightscoutClient? {
        let config = preferences.nightscout
        guard config.isConfigured, let url = config.normalizedBaseURL else { return nil }
        return NightscoutClient(baseURL: url, token: config.token)
    }

    /// Validates the configured site by fetching a single entry.
    func requestAccess() async throws {
        guard let client else {
            connectionState = .notConnected
            throw SourceError.integrationNotConfigured(source.displayName)
        }
        connectionState = .connecting
        do {
            _ = try await client.fetchEntries(count: 1)
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            throw error
        }
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        // sgv-only route, so the single newest entry is a real sensor reading.
        let latest = try await client.fetchEntries(count: 1)
        return latest.max { $0.timestamp < $1.timestamp }
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        // Server-side date filter drives the window; the count is only a safety
        // ceiling (≈2 weeks of 1-per-minute data) so nothing in-window is dropped.
        let recent = try await client.fetchEntries(since: date, count: 20_000)
        return recent.filter { $0.timestamp >= date }
    }

    /// Re-reads configuration and refreshes the connection state. Called by the
    /// settings screen after the user saves or clears the site.
    func refreshConnectionState() {
        connectionState = preferences.nightscout.isConfigured ? connectionState.reconciled : .notConnected
    }
}

private extension SourceConnectionState {
    /// Keeps a live `.connected`/`.failed` state but promotes a stale
    /// `.notConnected` to `.connected` once a site exists.
    var reconciled: SourceConnectionState {
        switch self {
        case .notConnected, .unavailable: return .connected
        default: return self
        }
    }
}
