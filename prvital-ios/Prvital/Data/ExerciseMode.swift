import Foundation

/// Workout mode: for its duration, the low-alert limit is raised (a fall from
/// 100 during movement deserves an early heads-up) and when it ends the session
/// logs itself as an activity entry — start it and forget it.
///
/// State is four small defaults values, so it survives relaunches and is
/// readable from any evaluation path without new plumbing.
enum ExerciseMode {
    private static let untilKey = "exercise.until"
    private static let startKey = "exercise.start"
    private static let typeKey = "exercise.typeRaw"
    private static let lowKey = "exercise.raisedLowMgdL"

    static func isActive(now: Date = Date()) -> Bool {
        (UserDefaults.standard.object(forKey: untilKey) as? Date).map { $0 > now } ?? false
    }

    static var activeType: ActivityType? {
        guard isActive() else { return nil }
        return UserDefaults.standard.string(forKey: typeKey).flatMap(ActivityType.init(rawValue:))
    }

    static var startedAt: Date? {
        UserDefaults.standard.object(forKey: startKey) as? Date
    }

    /// The raised low limit while a session runs, else nil.
    static func raisedLowMgdL(now: Date = Date()) -> Double? {
        guard isActive(now: now) else { return nil }
        let value = UserDefaults.standard.double(forKey: lowKey)
        return value > 0 ? value : nil
    }

    static func start(type: ActivityType, minutes: Int, raisedLowMgdL: Double, now: Date = Date()) {
        let defaults = UserDefaults.standard
        defaults.set(now, forKey: startKey)
        defaults.set(now.addingTimeInterval(TimeInterval(minutes * 60)), forKey: untilKey)
        defaults.set(type.rawValue, forKey: typeKey)
        defaults.set(raisedLowMgdL, forKey: lowKey)
    }

    /// Ends the session now (user tap) or after its planned end (background
    /// check), logging the REAL elapsed time through the normal write path.
    /// Returns true when a session was closed.
    @MainActor
    @discardableResult
    static func finish(entryStore: EntryStore, now: Date = Date(), force: Bool = false) -> Bool {
        let defaults = UserDefaults.standard
        guard let start = defaults.object(forKey: startKey) as? Date,
              let until = defaults.object(forKey: untilKey) as? Date else { return false }
        guard force || now >= until else { return false }

        let end = min(now, until)
        let seconds = max(60, Int(end.timeIntervalSince(start)))
        let type = defaults.string(forKey: typeKey).flatMap(ActivityType.init(rawValue:)) ?? .walking
        entryStore.addActivity(type: type, start: start, durationSeconds: seconds)

        defaults.removeObject(forKey: startKey)
        defaults.removeObject(forKey: untilKey)
        defaults.removeObject(forKey: typeKey)
        defaults.removeObject(forKey: lowKey)
        return true
    }
}
