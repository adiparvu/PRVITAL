import Foundation
import CryptoKit

/// One glucose measurement from LibreLinkUp — from either `graphData` or the
/// connection's latest `glucoseMeasurement`. `ValueInMgPerDl` is mg/dL. Both
/// stamps use `M/d/yyyy h:mm:ss a`, but `FactoryTimestamp` is the **UTC** instant
/// while `Timestamp` is the patient's local wall-clock — so the UTC one is what
/// pins a reading to an absolute time.
struct LibreGlucoseMeasurement: Decodable, Sendable {
    let valueInMgPerDl: Double
    let timestamp: String
    let factoryTimestamp: String?
    let trendArrow: Int?

    enum CodingKeys: String, CodingKey {
        case valueInMgPerDl = "ValueInMgPerDl"
        case timestamp = "Timestamp"
        case factoryTimestamp = "FactoryTimestamp"
        case trendArrow = "TrendArrow"
    }
}

/// Pure decoding helpers for LibreLinkUp — timestamp/trend parsing and sample
/// construction, all deterministic and unit-tested.
enum LibreLinkUpParsing {

    static func parseTimestamp(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return formatter.date(from: string)
    }

    /// LibreLinkUp's five trend arrows.
    static func trend(_ arrow: Int?) -> GlucoseTrend? {
        switch arrow {
        case 1: return .fallingFast
        case 2: return .falling
        case 3: return .stable
        case 4: return .rising
        case 5: return .risingFast
        default: return nil
        }
    }

    static func sample(from measurement: LibreGlucoseMeasurement) -> NormalizedGlucoseSample? {
        // Prefer the UTC FactoryTimestamp; fall back to the local Timestamp only
        // when it is absent (both are parsed with the UTC formatter).
        let stamp = measurement.factoryTimestamp ?? measurement.timestamp
        guard measurement.valueInMgPerDl > 0, let timestamp = parseTimestamp(stamp) else { return nil }
        return NormalizedGlucoseSample(
            id: "libre-\(Int(timestamp.timeIntervalSince1970))",
            valueMgdL: measurement.valueInMgPerDl,
            timestamp: timestamp,
            source: .freeStyleLibre,
            trend: trend(measurement.trendArrow),
            measurementType: .cgm
        )
    }

    /// The Account-Id header newer LibreLinkUp versions require: the hex SHA-256
    /// of the user id.
    static func accountIDHash(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Response shapes

private struct LibreLoginResponse: Decodable {
    let data: Payload?
    struct Payload: Decodable {
        let redirect: Bool?
        let region: String?
        let authTicket: AuthTicket?
        let user: User?
    }
    struct AuthTicket: Decodable { let token: String }
    struct User: Decodable { let id: String }
}

private struct LibreConnectionsResponse: Decodable {
    let data: [Connection]?
    struct Connection: Decodable { let patientId: String }
}

private struct LibreGraphResponse: Decodable {
    let data: Payload?
    struct Payload: Decodable {
        let connection: Connection?
        let graphData: [LibreGlucoseMeasurement]?
    }
    struct Connection: Decodable {
        let glucoseMeasurement: LibreGlucoseMeasurement?
        /// The worn sensor, when the account shares it: serial + activation
        /// epoch. This is what lets the session tracker start itself.
        let sensor: Sensor?
    }
    struct Sensor: Decodable {
        let sn: String?
        let a: Double?
    }
}

/// A `Sendable` HTTP client for the unofficial **LibreLinkUp** service (the
/// "follower" API behind the LibreLinkUp app). It logs in with the user's
/// LibreLinkUp account — handling the regional-server redirect — finds the first
/// shared patient, and reads the latest measurement plus the recent graph.
struct LibreLinkUpClient: Sendable {
    let credentials: SourceCredentials

    private static let product = "llu.ios"
    private static let version = "4.12.0"
    private static let defaultHost = "https://api.libreview.io"

    func fetchSamples() async throws -> [NormalizedGlucoseSample] {
        let session = try await login()
        let patientID = try await firstPatientID(session: session)
        return try await graph(session: session, patientID: patientID)
    }

    /// Validates credentials (used by the settings "test" action).
    @discardableResult
    func validate() async throws -> Session {
        try await login()
    }

    struct Session: Sendable {
        let token: String
        let host: String
        let userID: String
    }

    // MARK: Steps

    private func login() async throws -> Session {
        var host = Self.defaultHost
        let body = try JSONSerialization.data(withJSONObject: [
            "email": credentials.username, "password": credentials.password,
        ])
        // At most one region redirect.
        for _ in 0..<2 {
            let request = try makeRequest("\(host)/llu/auth/login", method: "POST", session: nil, body: body)
            let response: LibreLoginResponse = try await send(request)
            guard let payload = response.data else { throw SourceError.notAuthorized }

            if payload.redirect == true, let region = payload.region, !region.isEmpty {
                host = "https://api-\(region).libreview.io"
                continue
            }
            if let token = payload.authTicket?.token, let userID = payload.user?.id {
                return Session(token: token, host: host, userID: userID)
            }
            throw SourceError.notAuthorized
        }
        throw SourceError.notAuthorized
    }

    private func firstPatientID(session: Session) async throws -> String {
        let request = try makeRequest("\(session.host)/llu/connections", method: "GET", session: session, body: nil)
        let response: LibreConnectionsResponse = try await send(request)
        guard let patientID = response.data?.first?.patientId else {
            throw SourceError.integrationNotConfigured("LibreLinkUp (no shared sensor)")
        }
        return patientID
    }

    private func graph(session: Session, patientID: String) async throws -> [NormalizedGlucoseSample] {
        let request = try makeRequest("\(session.host)/llu/connections/\(patientID)/graph",
                                      method: "GET", session: session, body: nil)
        let response: LibreGraphResponse = try await send(request)

        // LibreLinkUp is the one feed that names the worn sensor outright —
        // hand its serial + activation to the auto session tracker.
        if let sensor = response.data?.connection?.sensor,
           let serial = sensor.sn, let activated = sensor.a, activated > 0 {
            LibreSensorSignal.report(
                serial: serial, activatedAt: Date(timeIntervalSince1970: activated))
        }

        var measurements = response.data?.graphData ?? []
        if let latest = response.data?.connection?.glucoseMeasurement {
            measurements.append(latest)
        }
        return measurements.compactMap(LibreLinkUpParsing.sample(from:))
    }

    // MARK: Plumbing

    private func makeRequest(_ urlString: String, method: String, session: Session?, body: Data?) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw SourceError.underlying("Invalid LibreLinkUp URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.product, forHTTPHeaderField: "product")
        request.setValue(Self.version, forHTTPHeaderField: "version")
        if let session {
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
            request.setValue(LibreLinkUpParsing.accountIDHash(session.userID), forHTTPHeaderField: "Account-Id")
        }
        request.httpBody = body
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.underlying("No response from LibreLinkUp.")
        }
        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401, 403, 430:
            throw SourceError.notAuthorized
        default:
            throw SourceError.underlying("LibreLinkUp returned HTTP \(http.statusCode).")
        }
    }
}
