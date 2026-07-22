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
            connectionState = .failed(Self.friendlyMessage(for: error))
            throw error
        }
    }

    /// The raw system error is English and can be an opaque provisioning message
    /// ("Missing com.apple.developer.healthkit entitlement."). Show a clear,
    /// localized line instead — the specific entitlement case gets its own copy so
    /// the user isn't staring at an internal identifier.
    private static func friendlyMessage(for error: Error) -> String {
        if error.localizedDescription.localizedCaseInsensitiveContains("entitlement") {
            return PrvitalString("Apple Health isn't available on this build yet.")
        }
        return PrvitalString("Couldn't connect to Apple Health.")
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        try await service.fetchLatestGlucose()
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        try await service.fetchGlucoseSamples(since: date)
    }
}

/// Dexcom (Dexcom One+, G6, G7, …) via the unofficial **Dexcom Share** service —
/// the same endpoint the Dexcom Follow app uses. The user signs in with their
/// Dexcom account (stored in the Keychain); readings then arrive automatically.
@MainActor
final class DexcomGlucoseSource: GlucoseSource {
    let source: DataSource = .dexcom
    private let store = SourceCredentialStore.shared
    private(set) var connectionState: SourceConnectionState

    init() {
        connectionState = SourceCredentialStore.shared.hasCredentials(for: .dexcom) ? .connected : .notConnected
    }

    /// A network source is always "available"; syncing depends on credentials.
    var isAvailable: Bool { true }

    private var client: DexcomShareClient? {
        guard let credentials = store.read(for: .dexcom), credentials.isComplete else { return nil }
        return DexcomShareClient(credentials: credentials)
    }

    func requestAccess() async throws {
        guard let client else {
            connectionState = .notConnected
            throw SourceError.integrationNotConfigured(source.displayName)
        }
        connectionState = .connecting
        do {
            _ = try await client.authenticate()
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            throw error
        }
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        return try await client.fetchSamples(minutes: 60, maxCount: 1).max { $0.timestamp < $1.timestamp }
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        let minutes = max(1, min(1440, Int(Date().timeIntervalSince(date) / 60)))
        let samples = try await client.fetchSamples(minutes: minutes, maxCount: 288)
        return samples.filter { $0.timestamp >= date }
    }

    func refreshConnectionState() {
        connectionState = store.hasCredentials(for: .dexcom) ? .connected : .notConnected
    }
}

/// FreeStyle Libre (Libre 2, Libre 3, …) via the unofficial **LibreLinkUp**
/// follower API. The user signs in with their LibreLinkUp account (stored in the
/// Keychain) and shares a sensor; the latest reading and recent graph sync in.
@MainActor
final class LibreGlucoseSource: GlucoseSource {
    let source: DataSource = .freeStyleLibre
    private let store = SourceCredentialStore.shared
    private(set) var connectionState: SourceConnectionState

    init() {
        connectionState = SourceCredentialStore.shared.hasCredentials(for: .freeStyleLibre) ? .connected : .notConnected
    }

    var isAvailable: Bool { true }

    private var client: LibreLinkUpClient? {
        guard let credentials = store.read(for: .freeStyleLibre), credentials.isComplete else { return nil }
        return LibreLinkUpClient(credentials: credentials)
    }

    func requestAccess() async throws {
        guard let client else {
            connectionState = .notConnected
            throw SourceError.integrationNotConfigured(source.displayName)
        }
        connectionState = .connecting
        do {
            _ = try await client.validate()
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            throw error
        }
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        return try await client.fetchSamples().max { $0.timestamp < $1.timestamp }
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        guard let client else { throw SourceError.integrationNotConfigured(source.displayName) }
        return try await client.fetchSamples().filter { $0.timestamp >= date }
    }

    func refreshConnectionState() {
        connectionState = store.hasCredentials(for: .freeStyleLibre) ? .connected : .notConnected
    }
}
