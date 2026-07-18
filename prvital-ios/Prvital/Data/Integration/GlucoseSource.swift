import Foundation

/// A source-agnostic glucose sample as it crosses the **integration boundary**.
///
/// Every provider — Dexcom, FreeStyle Libre, Apple Health, manual entry — emits
/// this same shape. The normalization layer is the only code that turns it into
/// a persisted `GlucoseReading`, so the domain never sees a vendor format.
struct NormalizedGlucoseSample: Identifiable, Sendable, Equatable {
    /// Source-native identifier, used to deduplicate re-imports of one reading.
    let id: String
    let valueMgdL: Double
    let timestamp: Date
    let source: DataSource
    var trend: GlucoseTrend?
    var measurementType: GlucoseMeasurementType = .cgm
    var sensorTimestamp: Date?
    var confidence: Double?
    var deviceID: String?
}

/// Connection lifecycle for a source, surfaced in Settings → Sources.
enum SourceConnectionState: Equatable, Sendable {
    case unavailable          // hardware / SDK not present on this device
    case notConnected         // available but the user hasn't linked it
    case needsAuthorization   // linked, waiting on a system permission
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool { self == .connected }
}

enum SourceError: LocalizedError {
    case notAuthorized
    case unavailable
    case integrationNotConfigured(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Access to this source hasn't been granted."
        case .unavailable: return "This source isn't available on this device."
        case .integrationNotConfigured(let name):
            return "\(name) needs to be linked in Settings before it can sync."
        case .underlying(let message): return message
        }
    }
}

/// The abstraction every glucose source conforms to. Adding a new sensor means
/// adding one conformer and registering it — no UI or domain change required.
@MainActor
protocol GlucoseSource: AnyObject {
    var source: DataSource { get }
    var displayName: String { get }
    /// Whether the underlying hardware / SDK exists on this device.
    var isAvailable: Bool { get }
    var connectionState: SourceConnectionState { get }

    /// Runs the consent explanation + system authorization for this source.
    func requestAccess() async throws
    /// The most recent sample, for the dashboard's "current glucose".
    func fetchLatest() async throws -> NormalizedGlucoseSample?
    /// All samples at or after `date`, for backfill and periodic sync.
    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample]
}

extension GlucoseSource {
    var displayName: String { source.displayName }
}
