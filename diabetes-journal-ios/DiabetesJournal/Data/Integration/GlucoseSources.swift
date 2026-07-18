import Foundation

/// Manual entry. Always available; values are written straight to the store by
/// the journal, so there is nothing to fetch.
@MainActor
final class ManualGlucoseSource: GlucoseSource {
    let source: DataSource = .manual
    var isAvailable: Bool { true }
    var connectionState: SourceConnectionState { .connected }

    func requestAccess() async throws {}
    func fetchLatest() async throws -> NormalizedGlucoseSample? { nil }
    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] { [] }
}

/// Apple Health as a glucose source. Delegates to `HealthKitService`.
@MainActor
final class HealthKitGlucoseSource: GlucoseSource {
    let source: DataSource = .appleHealth
    private let service: HealthKitService
    private(set) var connectionState: SourceConnectionState = .notConnected

    init(service: HealthKitService) { self.service = service }

    var isAvailable: Bool { service.isAvailable }

    func requestAccess() async throws {
        guard isAvailable else { connectionState = .unavailable; throw SourceError.unavailable }
        connectionState = .connecting
        do {
            try await service.requestAuthorization()
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            throw error
        }
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        try await service.fetchLatestGlucose()
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        try await service.fetchGlucoseSamples(since: date)
    }
}

/// Dexcom (Dexcom One+, G6, G7, …).
///
/// **Extension point.** A production build links this to Dexcom data through an
/// official channel — Apple Health (Dexcom writes there), the Dexcom Share /
/// partner API with the user's credentials, or a bundled vendor SDK. Until a
/// build is configured with those, the source reports itself as not-configured
/// rather than inventing values, and never fabricates readings.
@MainActor
final class DexcomGlucoseSource: GlucoseSource {
    let source: DataSource = .dexcom
    private(set) var connectionState: SourceConnectionState = .notConnected

    /// Flip to `true` in a build wired to a real Dexcom integration.
    var isConfigured = false
    var isAvailable: Bool { isConfigured }

    func requestAccess() async throws {
        guard isConfigured else {
            connectionState = .notConnected
            throw SourceError.integrationNotConfigured(source.displayName)
        }
        connectionState = .connected
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        guard isConfigured else { throw SourceError.integrationNotConfigured(source.displayName) }
        return nil // Wire to the Dexcom API / SDK here.
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        guard isConfigured else { throw SourceError.integrationNotConfigured(source.displayName) }
        return []
    }
}

/// FreeStyle Libre (Libre 2, Libre 3, …).
///
/// **Extension point**, same contract as Dexcom: link through Apple Health,
/// LibreLinkUp, or a vendor SDK in a configured build.
@MainActor
final class LibreGlucoseSource: GlucoseSource {
    let source: DataSource = .freeStyleLibre
    private(set) var connectionState: SourceConnectionState = .notConnected

    var isConfigured = false
    var isAvailable: Bool { isConfigured }

    func requestAccess() async throws {
        guard isConfigured else {
            connectionState = .notConnected
            throw SourceError.integrationNotConfigured(source.displayName)
        }
        connectionState = .connected
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        guard isConfigured else { throw SourceError.integrationNotConfigured(source.displayName) }
        return nil
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        guard isConfigured else { throw SourceError.integrationNotConfigured(source.displayName) }
        return []
    }
}
