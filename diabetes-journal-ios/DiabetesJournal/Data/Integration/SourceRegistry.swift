import Foundation
import Observation

/// Holds the registered glucose sources and the user's **primary source**
/// choice, which drives both provenance display and conflict priority.
///
/// Registering a new sensor is a one-line change here; nothing else in the app
/// needs to know the concrete source types.
@MainActor
@Observable
final class SourceRegistry {
    private let sourcesByType: [DataSource: GlucoseSource]

    /// The user's preferred glucose source. Persisted across launches.
    var primarySource: DataSource {
        didSet {
            let defaults = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
            defaults.set(primarySource.rawValue, forKey: Self.primaryKey)
        }
    }
    private static let primaryKey = "com.diabetesjournal.primarySource"

    /// Canonical fallback order used to complete the priority list.
    private static let canonicalOrder: [DataSource] =
        [.dexcom, .freeStyleLibre, .otherCGM, .appleHealth, .appleWatch, .manual]

    init(sources: [GlucoseSource], defaultPrimary: DataSource = .appleHealth) {
        self.sourcesByType = Dictionary(uniqueKeysWithValues: sources.map { ($0.source, $0) })
        let defaults = UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        let stored = defaults.string(forKey: Self.primaryKey).flatMap(DataSource.init(rawValue:))
        self.primarySource = stored ?? defaultPrimary
    }

    func source(for type: DataSource) -> GlucoseSource? { sourcesByType[type] }

    /// All registered sources, primary first, then canonical order.
    var orderedSources: [GlucoseSource] {
        sourcePriority.compactMap { sourcesByType[$0] }
    }

    /// The priority list handed to `ConflictResolver`: primary, then the rest.
    var sourcePriority: [DataSource] {
        [primarySource] + Self.canonicalOrder.filter { $0 != primarySource }
    }

    func connectedSources() -> [GlucoseSource] {
        orderedSources.filter { $0.connectionState.isConnected }
    }
}
