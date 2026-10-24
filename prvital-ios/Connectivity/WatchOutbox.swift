import Foundation
import Observation

/// What the watch has sent and not yet seen confirmed — the truth behind the
/// word "Logged".
///
/// An entry is `sending` while the phone is reachable and has not answered,
/// `queued` when the phone is out of reach (WatchConnectivity holds it and
/// delivers later), and `logged` once the phone has confirmed it wrote the
/// entry. Only the watch uses it; it lives with the bridge so the app target
/// can test it.
@MainActor
@Observable
final class WatchOutbox {
    static let shared = WatchOutbox()

    enum State: Equatable, Sendable {
        case sending
        case queued
        case logged
    }

    struct Item: Equatable, Sendable {
        let kind: String
        let amount: Double
        var state: State
    }

    private(set) var items: [UUID: Item] = [:]

    init() {}

    /// Entries the phone has not confirmed yet.
    var waitingCount: Int {
        items.values.filter { $0.state != .logged }.count
    }

    func state(of id: UUID) -> State? {
        items[id]?.state
    }

    func add(id: UUID, kind: String, amount: Double, state: State) {
        items[id] = Item(kind: kind, amount: amount, state: state)
    }

    /// The phone could not be reached after all; the entry rides the queue.
    func markQueued(_ id: UUID) {
        guard var item = items[id], item.state == .sending else { return }
        item.state = .queued
        items[id] = item
    }

    /// The phone confirmed the entry is logged. The row lingers briefly so the
    /// confirmation can still be shown, then disappears.
    func markLogged(_ id: UUID, lingering: Duration = .seconds(10)) {
        guard var item = items[id] else { return }
        item.state = .logged
        items[id] = item
        Task {
            try? await Task.sleep(for: lingering)
            items[id] = nil
        }
    }
}
