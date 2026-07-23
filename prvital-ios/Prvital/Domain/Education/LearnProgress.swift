import Foundation

/// Tracks which encyclopedia articles the reader has finished, so the Learn hub
/// can show a real sense of progress — the "academy" feel — without any account,
/// server, or SwiftData model. Pure value logic; the view persists it as a small
/// string via `@AppStorage`.
///
/// The count and completion are always computed *against the current library's
/// IDs*, so an article removed in a later app version can never inflate the
/// progress past 100%.
struct LearnProgress: Equatable, Sendable {
    /// The IDs of articles the reader has opened / finished.
    private(set) var readIDs: Set<String>

    init(readIDs: Set<String> = []) { self.readIDs = readIDs }

    func isRead(_ id: String) -> Bool { readIDs.contains(id) }

    mutating func markRead(_ id: String) { readIDs.insert(id) }

    /// How many of the given article IDs are read. Stale IDs (no longer in the
    /// library) are ignored, so this never exceeds `ids.count`.
    func readCount(among ids: [String]) -> Int {
        ids.reduce(0) { $0 + (readIDs.contains($1) ? 1 : 0) }
    }

    /// Completion in `0...1` across the given IDs (0 for an empty library).
    func fraction(among ids: [String]) -> Double {
        guard !ids.isEmpty else { return 0 }
        return Double(readCount(among: ids)) / Double(ids.count)
    }

    /// The first ID in reading order that hasn't been read yet — what the hub
    /// suggests reading next. `nil` once everything is read (or the list is empty).
    func firstUnread(among ids: [String]) -> String? {
        ids.first { !readIDs.contains($0) }
    }

    /// True when every article in the (non-empty) library is read.
    func isComplete(among ids: [String]) -> Bool {
        !ids.isEmpty && firstUnread(among: ids) == nil
    }

    // MARK: - Compact persistence

    /// Decodes the storage format: IDs joined by a tab. A tab is used as the
    /// separator because article IDs may contain spaces or commas but never a tab.
    static func decode(_ stored: String) -> LearnProgress {
        let ids = stored
            .split(separator: "\t", omittingEmptySubsequences: true)
            .map(String.init)
        return LearnProgress(readIDs: Set(ids))
    }

    /// Encodes to the storage format, sorted so the stored string is stable and
    /// order-independent (equal sets round-trip to equal strings).
    func encoded() -> String {
        readIDs.sorted().joined(separator: "\t")
    }
}
