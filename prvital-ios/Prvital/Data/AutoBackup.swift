import Foundation
import SwiftData

/// The weekly safety net: writes the same full-journal JSON the manual export
/// produces into Documents/Backups, once a week, keeping the last four. The
/// folder is visible in the Files app (On My iPhone → Prvital), so the backups
/// are the user's even if the phone never sees iTunes or a Mac.
@MainActor
enum AutoBackup {
    static let enabledKey = "backup.autoWeeklyEnabled"
    static let lastRunKey = "backup.lastAutoBackupAt"
    nonisolated static let keepCount = 4

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Runs at most once every 7 days; cheap no-op otherwise. Called from the
    /// background-refresh path, so the week's backup lands without the app
    /// ever being opened.
    static func runIfDue(modelContainer: ModelContainer, now: Date = Date()) {
        guard isEnabled else { return }
        let last = UserDefaults.standard.object(forKey: lastRunKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= 7 * 86_400 else { return }
        UserDefaults.standard.set(now, forKey: lastRunKey)

        let store = JournalBackupStore(modelContainer: modelContainer)
        Task.detached(priority: .utility) {
            guard let documents = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask).first else { return }
            let folder = documents.appendingPathComponent("Backups", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            guard let temp = try? await store.writeBackupFile() else { return }
            let destination = folder.appendingPathComponent(temp.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: temp, to: destination)

            // Keep the newest `keepCount`, drop the rest.
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "json" }
                .sorted { lhs, rhs in
                    let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    return l > r
                }
            for stale in files.dropFirst(keepCount) {
                try? FileManager.default.removeItem(at: stale)
            }
        }
    }
}
