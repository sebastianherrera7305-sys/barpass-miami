import Foundation
import Network

/// Actions taken inside a venue that must NOT depend on the network being
/// usable at that moment.
///
/// TestFlight, 2026-09-11: "tooo slow inside of the club, too hard for people
/// to even use it, like it's impossible" — and then the real question: "por
/// qué me debería quedar con BarPass si no funciona adentro de un club".
/// Fair. Inside a packed venue the LTE is contended to the point of uselessness,
/// and that is exactly where checking in, posting a photo and reporting what a
/// drink cost are supposed to happen. Before this, each of those blocked on a
/// live round trip with no timeout (60s default), then failed with an error and
/// lost the action entirely.
///
/// The rule now: the action succeeds locally the instant the user takes it, and
/// the network catches up whenever it can — on reconnect, on foreground, or on
/// the next launch. This mirrors the local-first pattern PostRepository already
/// used for venue posts; this generalises it to everything done in-venue.
///
/// Deliberately simple: a small JSON file, at most `maxQueued` entries, each
/// with a bounded number of attempts. Nothing here is worth a database.
@MainActor
final class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    /// One queued action. `payload` carries whatever the specific kind needs;
    /// keeping it a flat dictionary means a new action type doesn't invalidate
    /// everything already on disk from an older version of the app.
    struct PendingAction: Codable, Identifiable, Equatable {
        enum Kind: String, Codable {
            case checkIn
            case ageReport
            case priceReport
            case venueMedia
        }
        let id: UUID
        let kind: Kind
        let payload: [String: String]
        let createdAt: Date
        var attempts: Int

        init(kind: Kind, payload: [String: String]) {
            self.id = UUID()
            self.kind = kind
            self.payload = payload
            self.createdAt = Date()
            self.attempts = 0
        }
    }

    /// Shown in the UI so the user knows something is still on its way rather
    /// than silently lost.
    @Published private(set) var pending: [PendingAction] = []

    /// A night out is a few dozen actions at most. A cap keeps a permanently
    /// failing action from growing the file without bound.
    private static let maxQueued = 200
    /// After this many failed attempts the action is dropped: something about
    /// it is wrong (a deleted venue, a revoked session) and retrying forever
    /// would just burn battery on every reconnect.
    private static let maxAttempts = 8

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BarPassOfflineQueue.json")
    }()

    private let monitor = NWPathMonitor()
    private var isFlushing = false
    /// Set by the app at startup — the queue doesn't know how to perform any
    /// action itself, which keeps it free of every repository it serves.
    var perform: ((PendingAction) async throws -> Void)?

    private init() {
        pending = Self.read()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "barpass.offlinequeue.monitor"))
    }

    // MARK: - Enqueue

    func enqueue(_ kind: PendingAction.Kind, _ payload: [String: String]) {
        guard pending.count < Self.maxQueued else { return }
        pending.append(PendingAction(kind: kind, payload: payload))
        persist()
        Task { await flush() }
    }

    /// How many of a kind are still waiting — for a "subiendo…" badge.
    func pendingCount(of kind: PendingAction.Kind) -> Int {
        pending.filter { $0.kind == kind }.count
    }

    // MARK: - Flush

    /// Safe to call as often as you like: foreground, reconnect, launch.
    func flush() async {
        guard !isFlushing, !pending.isEmpty, let perform else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Oldest first, so the night replays in the order it happened.
        for action in pending.sorted(by: { $0.createdAt < $1.createdAt }) {
            do {
                try await perform(action)
                remove(action.id)
            } catch {
                // One failure means the network is still bad; stop rather than
                // hammering the rest of the queue against the same wall.
                bumpAttempts(action.id)
                break
            }
        }
    }

    // MARK: - Storage

    private func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
        persist()
    }

    private func bumpAttempts(_ id: UUID) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].attempts += 1
        if pending[i].attempts >= Self.maxAttempts {
            pending.remove(at: i)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static func read() -> [PendingAction] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PendingAction].self, from: data)
        else { return [] }
        return decoded
    }
}
