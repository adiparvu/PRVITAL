import Foundation
import SwiftData

// MARK: - Value inputs
//
// The uploader never touches SwiftData models. `SyncCoordinator` snapshots the
// user's records into these plain `Sendable` values on the main actor first, so
// nothing model-bound ever crosses into the upload path.

/// A record type the upload planner can filter and order.
protocol NightscoutUploadValue: Sendable {
    var timestamp: Date { get }
    var source: DataSource { get }
}

/// A glucose value queued for upload.
struct NightscoutGlucoseUpload: NightscoutUploadValue, Equatable {
    var valueMgdL: Double
    var timestamp: Date
    var trend: GlucoseTrend?
    var source: DataSource
}

/// A carbohydrate entry queued for upload.
struct NightscoutCarbUpload: NightscoutUploadValue, Equatable {
    var grams: Double
    var timestamp: Date
    var source: DataSource
}

/// An insulin dose queued for upload.
struct NightscoutInsulinUpload: NightscoutUploadValue, Equatable {
    var units: Double
    var timestamp: Date
    /// `true` for a meal bolus (`eventType: "Meal Bolus"`); everything else
    /// uploads as `"Correction Bolus"`.
    var isMealBolus: Bool
    var source: DataSource
}

/// Everything one sync pass hands the uploader.
struct NightscoutPendingUpload: Sendable, Equatable {
    var glucose: [NightscoutGlucoseUpload] = []
    var carbs: [NightscoutCarbUpload] = []
    var insulin: [NightscoutInsulinUpload] = []

    var isEmpty: Bool { glucose.isEmpty && carbs.isEmpty && insulin.isEmpty }
}

// MARK: - Wire formats

/// One row for `POST api/v1/entries` — the same shape `NightscoutEntry` reads
/// back, so a Prvital-uploaded value round-trips through the fetch path cleanly.
struct NightscoutUploadEntry: Encodable, Sendable, Equatable {
    let type: String
    let sgv: Int
    let date: Int           // epoch milliseconds, matching the fetch side
    let dateString: String  // ISO 8601 with fractional seconds
    let direction: String
    let device: String
}

/// One row for `POST api/v1/treatments`. `carbs` and `insulin` are optionals so
/// the synthesized encoder omits whichever one a treatment doesn't carry.
struct NightscoutUploadTreatment: Encodable, Sendable, Equatable {
    let eventType: String
    let carbs: Double?
    let insulin: Double?
    let createdAt: String
    let device: String

    enum CodingKeys: String, CodingKey {
        case eventType, carbs, insulin, device
        case createdAt = "created_at"
    }
}

/// Pure model → wire-format mapping. Stateless and nonisolated so it is fully
/// unit-testable without an uploader instance.
enum NightscoutUploadPayload {
    /// The `device` tag stamped on every uploaded row, so Prvital's own uploads
    /// are identifiable on the site (and in any debugging session).
    static let deviceName = "prvital"

    static func entry(from record: NightscoutGlucoseUpload) -> NightscoutUploadEntry {
        NightscoutUploadEntry(
            type: "sgv",
            sgv: Int(record.valueMgdL.rounded()),
            date: Int(record.timestamp.timeIntervalSince1970 * 1000),
            dateString: iso8601(record.timestamp),
            direction: direction(from: record.trend),
            device: deviceName
        )
    }

    static func treatment(from record: NightscoutCarbUpload) -> NightscoutUploadTreatment {
        NightscoutUploadTreatment(
            eventType: "Carb Correction",
            carbs: record.grams,
            insulin: nil,
            createdAt: iso8601(record.timestamp),
            device: deviceName
        )
    }

    static func treatment(from record: NightscoutInsulinUpload) -> NightscoutUploadTreatment {
        NightscoutUploadTreatment(
            eventType: record.isMealBolus ? "Meal Bolus" : "Correction Bolus",
            carbs: nil,
            insulin: record.units,
            createdAt: iso8601(record.timestamp),
            device: deviceName
        )
    }

    /// The exact inverse of `NightscoutEntry.trend(from:)` on the fetch side.
    static func direction(from trend: GlucoseTrend?) -> String {
        switch trend {
        case .risingFast: return "DoubleUp"
        case .rising: return "SingleUp"
        case .stable: return "Flat"
        case .falling: return "SingleDown"
        case .fallingFast: return "DoubleDown"
        case nil: return "NONE"
        }
    }

    /// Fractional-second ISO 8601 (`…T12:00:00.000Z`), the form Nightscout
    /// itself writes for `dateString`/`created_at`. A fresh formatter per call
    /// mirrors `NightscoutEntry.parseISO` (`ISO8601DateFormatter` isn't Sendable,
    /// so it can't be cached in a static).
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Upload planning (pure, testable)

/// Watermark, eligibility and batching rules — pure functions so the dedup and
/// loop-prevention logic is testable without any networking or persistence.
enum NightscoutUploadPlanner {
    /// App-group defaults key holding the newest already-uploaded timestamp.
    static let watermarkKey = "ns.upload.watermark"
    /// Never look further back than this, even on a first-ever upload.
    static let maxLookback: TimeInterval = 7 * 24 * 60 * 60
    /// Nightscout uploads are chunked to at most this many rows per request.
    static let maxBatchSize = 100

    /// Where a gather pass starts: the watermark, floored at `maxLookback` ago.
    static func windowStart(watermark: Date?, now: Date = Date()) -> Date {
        let floor = now.addingTimeInterval(-maxLookback)
        guard let watermark else { return floor }
        return max(watermark, floor)
    }

    /// **LOOP GUARD** — the one filter that keeps uploads from echoing.
    ///
    /// Only records the user entered by hand (`source == .manual`) are ever
    /// eligible. Readings that arrived *from* Nightscout, Apple Health, a CGM or
    /// a meter must never round-trip back up, or every sync would re-import what
    /// the previous sync uploaded. The caller already fetches manual-only rows;
    /// this re-check makes the guarantee hold no matter who builds the values.
    ///
    /// On top of that, only records strictly newer than the watermark pass, so
    /// nothing is uploaded twice. Results are oldest-first so the site receives
    /// them in chronological order.
    static func eligible<T: NightscoutUploadValue>(_ records: [T], newerThan watermark: Date?) -> [T] {
        records
            .filter { $0.source == .manual }
            .filter { record in watermark.map { record.timestamp > $0 } ?? true }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Splits `items` into slices of at most `size` (order preserved).
    static func chunked<T>(_ items: [T], size: Int = maxBatchSize) -> [[T]] {
        guard size > 0, !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}

// MARK: - HTTP client

/// The write-side counterpart to `NightscoutClient`: same base URL handling,
/// same authentication (an optional `token` **query parameter** — the app never
/// uses the legacy SHA-1 `api-secret` header), same status handling.
struct NightscoutUploadClient: Sendable {
    let baseURL: URL
    let token: String

    /// POSTs `rows` as a JSON array to `<base>/<path>`.
    func post(_ rows: some Encodable & Sendable, to path: String) async throws {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SourceError.underlying("Invalid Nightscout URL.")
        }
        if !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        guard let url = components.url else {
            throw SourceError.underlying("Invalid Nightscout URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(rows)

        let (_, response) = try await URLSession.shared.data(for: request)

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
    }
}

// MARK: - Uploader

/// Mirrors the user's **own, manually entered** glucose, carb and insulin
/// records up to their Nightscout site (`POST api/v1/entries` / `treatments`).
///
/// Opt-in twice over: it only runs when `preferences.nightscoutUploadEnabled`
/// is on *and* a site is configured. It reads both from `Preferences` on every
/// call — like `NightscoutGlucoseSource` — so changes take effect on the next
/// sync without re-wiring.
///
/// Failures are quiet by design: an unreachable site is recorded in the audit
/// trail and retried naturally on the next sync (the watermark only advances on
/// success), never surfaced as a modal — matching how sync treats
/// configuration-state errors.
@MainActor
final class NightscoutUploader {
    private let preferences: Preferences
    private let audit: AuditService
    private let defaults: UserDefaults

    init(preferences: Preferences, audit: AuditService, defaults: UserDefaults? = nil) {
        self.preferences = preferences
        self.audit = audit
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    /// True only when the user turned uploading on *and* a site is configured.
    var isEnabled: Bool {
        preferences.nightscoutUploadEnabled && preferences.nightscout.isConfigured
    }

    /// Timestamp of the newest record already uploaded (the dedup watermark),
    /// or `nil` before the first successful upload.
    var lastUploadedAt: Date? {
        defaults.object(forKey: NightscoutUploadPlanner.watermarkKey) as? Date
    }

    /// Where the coordinator's gather pass should start: everything newer than
    /// the watermark, capped at 7 days back.
    func uploadWindowStart(now: Date = Date()) -> Date {
        NightscoutUploadPlanner.windowStart(watermark: lastUploadedAt, now: now)
    }

    /// Snapshots the user's **manual-only** records newer than `since` into
    /// plain values, ready to hand to `upload(_:)`. Runs on the main actor so
    /// SwiftData models never escape it.
    ///
    /// The `sourceRaw == manual` predicate is the primary loop guard: rows that
    /// came *from* Nightscout, Apple Health, a CGM or a meter are never fetched,
    /// so they can never round-trip back to the site.
    static func gatherPending(in context: ModelContext, since: Date) -> NightscoutPendingUpload {
        let manualRaw = DataSource.manual.rawValue
        var pending = NightscoutPendingUpload()

        let readings = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp > since && $0.sourceRaw == manualRaw && $0.isActive },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        pending.glucose = ((try? context.fetch(readings)) ?? []).map {
            NightscoutGlucoseUpload(valueMgdL: $0.valueMgdL, timestamp: $0.timestamp,
                                    trend: $0.trend, source: $0.source)
        }

        let carbs = FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp > since && $0.sourceRaw == manualRaw },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        pending.carbs = ((try? context.fetch(carbs)) ?? []).map {
            NightscoutCarbUpload(grams: $0.grams, timestamp: $0.timestamp, source: $0.source)
        }

        let insulin = FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp > since && $0.sourceRaw == manualRaw },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        pending.insulin = ((try? context.fetch(insulin)) ?? []).map {
            NightscoutInsulinUpload(units: $0.units, timestamp: $0.timestamp,
                                    isMealBolus: $0.doseContext == .mealBolus, source: $0.source)
        }

        return pending
    }

    /// Uploads the pending values, at most 100 rows per request, then advances
    /// the watermark past everything sent. A no-op unless enabled and there is
    /// something eligible. Errors are audited, not surfaced; the un-advanced
    /// watermark makes the next sync retry the same window.
    func upload(_ pending: NightscoutPendingUpload) async {
        guard isEnabled, let baseURL = preferences.nightscout.normalizedBaseURL else { return }

        // Re-apply the manual-only guard and the watermark filter to whatever
        // the caller gathered — defense in depth against upload loops.
        let watermark = lastUploadedAt
        let glucose = NightscoutUploadPlanner.eligible(pending.glucose, newerThan: watermark)
        let carbs = NightscoutUploadPlanner.eligible(pending.carbs, newerThan: watermark)
        let insulin = NightscoutUploadPlanner.eligible(pending.insulin, newerThan: watermark)
        guard !(glucose.isEmpty && carbs.isEmpty && insulin.isEmpty) else { return }

        let entries = glucose.map { NightscoutUploadPayload.entry(from: $0) }
        let carbTreatments = carbs.map { NightscoutUploadPayload.treatment(from: $0) }
        let insulinTreatments = insulin.map { NightscoutUploadPayload.treatment(from: $0) }
        let treatments = carbTreatments + insulinTreatments
        let client = NightscoutUploadClient(baseURL: baseURL, token: preferences.nightscout.token)

        do {
            for chunk in NightscoutUploadPlanner.chunked(entries) {
                try await client.post(chunk, to: "api/v1/entries")
            }
            for chunk in NightscoutUploadPlanner.chunked(treatments) {
                try await client.post(chunk, to: "api/v1/treatments")
            }

            let newest = (glucose.map(\.timestamp) + carbs.map(\.timestamp) + insulin.map(\.timestamp)).max()
            if let newest {
                defaults.set(newest, forKey: NightscoutUploadPlanner.watermarkKey)
            }
            audit.log(.sync, source: .nightscout, result: .success,
                      detail: "Uploaded \(entries.count) reading(s), \(treatments.count) treatment(s) to Nightscout")
        } catch {
            // Quiet failure: audit only. The watermark did not advance, so the
            // next sync retries the same window automatically.
            audit.log(.sync, source: .nightscout, result: .failure,
                      detail: "Nightscout upload failed: \(error.localizedDescription)")
        }
    }
}
