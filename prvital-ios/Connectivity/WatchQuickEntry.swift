import Foundation

/// One entry sent from the wrist to the phone, with what a medication log
/// cannot do without: WHEN it happened and WHICH entry it is.
///
/// The watch stamps the moment of the tap and a unique id. The phone logs the
/// entry at the wrist's time — not at the (possibly much later) moment a queued
/// transfer finally arrives — and ignores an id it has already logged, so a
/// retried transfer can never double a dose. A watch that predates both fields
/// still works: no id means "always log", no stamp means "log now".
struct WatchEntryRequest: Equatable, Sendable {
    /// "insulin", "carbs" or "glucose" (mg/dL).
    var kind: String
    /// Units, grams or mg/dL, matching `kind`.
    var amount: Double
    /// Nil from a watch build that predates ids.
    var id: UUID?
    /// When the entry was tapped on the wrist; nil from a watch that predates it.
    var sentAt: Date?

    static let validKinds: Set<String> = ["insulin", "carbs", "glucose"]

    /// How far into the future a wrist clock may run before it is not trusted.
    static let futureTolerance: TimeInterval = 5 * 60
    /// How old an entry may be and still keep its own time. Older than this the
    /// timestamp is more likely a wrong clock than a real delay.
    static let maxAge: TimeInterval = 48 * 3600

    init(kind: String, amount: Double, id: UUID? = nil, sentAt: Date? = nil) {
        self.kind = kind
        self.amount = amount
        self.id = id
        self.sentAt = sentAt
    }

    /// Parses a WatchConnectivity payload. Nil for anything that is not a
    /// well-formed entry — unknown kind, missing or non-positive amount.
    init?(payload: [String: Any]) {
        guard let kind = payload["kind"] as? String, Self.validKinds.contains(kind),
              let amount = payload["amount"] as? Double, amount.isFinite, amount > 0
        else { return nil }
        self.kind = kind
        self.amount = amount
        self.id = (payload["id"] as? String).flatMap(UUID.init(uuidString:))
        self.sentAt = (payload["ts"] as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    /// The wire form. Keys are stable across versions; unknown ones are ignored
    /// by older receivers.
    static func payload(kind: String, amount: Double, id: UUID, stamp: TimeInterval) -> [String: Any] {
        ["kind": kind, "amount": amount, "id": id.uuidString, "ts": stamp]
    }

    /// The time the entry should be logged at: the wrist's own tap time when it
    /// is plausible, otherwise `now`.
    func loggedAt(now: Date = Date()) -> Date {
        guard let sentAt else { return now }
        if sentAt > now.addingTimeInterval(Self.futureTolerance) { return now }
        if sentAt < now.addingTimeInterval(-Self.maxAge) { return now }
        return sentAt
    }
}

/// Remembers which watch entries were already logged, so the same id arriving
/// twice (a retried transfer, a replayed queue) is logged exactly once.
///
/// Small on purpose: ids older than a week are forgotten and at most 200 are
/// kept. Thread-safe — the connectivity callbacks arrive off the main thread.
final class WatchEntryLedger: @unchecked Sendable {
    static let shared = WatchEntryLedger()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "watch.entryLedger"
    private let capacity = 200
    private let retention: TimeInterval = 7 * 86_400

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True the first time an id is seen (and records it); false for a repeat.
    /// An entry without an id can't be told apart from another, so it always passes.
    func claim(_ id: UUID?, now: Date = Date()) -> Bool {
        guard let id else { return true }
        lock.lock()
        defer { lock.unlock() }

        let nowStamp = now.timeIntervalSince1970
        var seen = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        seen = seen.filter { $0.value >= nowStamp - retention }
        if seen[id.uuidString] != nil {
            defaults.set(seen, forKey: key)
            return false
        }
        seen[id.uuidString] = nowStamp
        if seen.count > capacity {
            let newest = seen.sorted { $0.value > $1.value }.prefix(capacity)
            seen = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        defaults.set(seen, forKey: key)
        return true
    }
}
