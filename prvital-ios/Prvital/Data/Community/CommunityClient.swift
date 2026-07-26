import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

/// The community leaderboard's storage: one record per opted-in user in the
/// app's PUBLIC CloudKit database — Apple's shared backend, no server of our
/// own. The record carries ONLY the pseudonym, badge points, badge-level count
/// and country/continent; never a glucose value or any medical datum.
///
/// The record name is a random UUID persisted locally, so the entry is
/// pseudonymous and can always be updated or deleted by its owner.
///
/// A value type with no stored state — every member is a computed property or
/// an async call against thread-safe system objects — so it is freely Sendable
/// and safe to create anywhere (e.g. a View's default member initializer).
struct CommunityClient: Sendable {
    static let containerIdentifier = "iCloud.com.prvital"
    static let recordType = "LeaderboardEntry"

    private static let recordUUIDKey = "community.recordUUID"
    private static let lastPublishedKey = "community.lastPublishedPoints"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroupIdentifier) ?? .standard
    }

    /// Stable pseudonymous record name for this device's entry.
    private var recordName: String {
        if let existing = defaults.string(forKey: Self.recordUUIDKey) { return existing }
        let fresh = "lb-" + UUID().uuidString
        defaults.set(fresh, forKey: Self.recordUUIDKey)
        return fresh
    }

    #if canImport(CloudKit)
    private var database: CKDatabase {
        CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase
    }

    /// Whether an iCloud account is signed in (required to WRITE to the public
    /// database; reading works without one).
    func accountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: Self.containerIdentifier).accountStatus()
        return status == .available
    }

    /// Creates or updates this user's entry. Skips the network entirely when
    /// the points haven't changed since the last successful publish.
    func publish(handle: String, points: Int, badges: Int, country: String, force: Bool = false) async throws {
        if !force, defaults.integer(forKey: Self.lastPublishedKey) == points { return }
        let id = CKRecord.ID(recordName: recordName)
        let record: CKRecord
        if let existing = try? await database.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record["handle"] = String(handle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        record["points"] = points
        record["badges"] = badges
        record["country"] = country.uppercased()
        record["continent"] = WorldContinents.continent(forCountry: country) ?? "??"
        _ = try await database.save(record)
        defaults.set(points, forKey: Self.lastPublishedKey)
    }

    /// Removes this user's entry (opt-out). Missing records count as success.
    func withdraw() async throws {
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — exactly the state we want.
        }
        defaults.removeObject(forKey: Self.lastPublishedKey)
    }

    /// The top of a board, best first, capped at 50 rows.
    func top(scope: LeaderboardScope, country: String) async throws -> [LeaderboardEntry] {
        let predicate: NSPredicate
        switch scope {
        case .global:
            predicate = NSPredicate(value: true)
        case .country:
            predicate = NSPredicate(format: "country == %@", country.uppercased())
        case .continent:
            let continent = WorldContinents.continent(forCountry: country) ?? "??"
            predicate = NSPredicate(format: "continent == %@", continent)
        }
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "points", ascending: false)]
        let (results, _) = try await database.records(matching: query, resultsLimit: 50)
        let mine = recordName
        return results.compactMap { id, result in
            guard let record = try? result.get() else { return nil }
            return LeaderboardEntry(
                id: id.recordName,
                handle: record["handle"] as? String ?? "—",
                points: record["points"] as? Int ?? 0,
                badges: record["badges"] as? Int ?? 0,
                country: record["country"] as? String ?? "",
                continentRaw: record["continent"] as? String ?? "",
                isMe: id.recordName == mine
            )
        }
    }
    #endif
}
