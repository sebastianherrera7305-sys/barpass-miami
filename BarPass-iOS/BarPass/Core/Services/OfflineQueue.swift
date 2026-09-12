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

// MARK: - Pending lookups used by the UI

extension OfflineQueue {
    /// True when an action of this kind for this venue is still waiting.
    /// Views use it to show "subiendo…" instead of either a plain success
    /// (a lie — nothing has reached the server yet) or an error (also a
    /// lie — it WILL be retried).
    func hasPending(_ kind: PendingAction.Kind, venueId: String) -> Bool {
        pending.contains { $0.kind == kind && $0.payload["venueId"] == venueId }
    }
}

// MARK: - Bounded live attempt

/// What happened when we tried to do the thing live before falling back to
/// the queue.
enum OfflineAttempt: Sendable {
    /// It landed. Nothing was queued.
    case succeeded
    /// It didn't land in time, or failed for a reason a retry can fix.
    case queue
    /// It failed for a reason no retry can fix (an underage user, a missing
    /// birthdate). The message is already localized and meant for the user.
    case permanentFailure(String)
}

extension OfflineQueue {
    /// Runs `op`, but never lets the user wait on contended venue LTE for
    /// longer than `seconds`. Past the deadline the in-flight task is
    /// cancelled (so nothing lands twice) and the caller enqueues instead.
    ///
    /// `classify` turns an error into a user-facing message when retrying
    /// is pointless; returning nil means "queue it and try again later".
    static func attempt(
        seconds: Double,
        classify: @escaping @Sendable (Error) -> String? = { _ in nil },
        operation: @escaping @Sendable () async throws -> Void
    ) async -> OfflineAttempt {
        await withTaskGroup(of: OfflineAttempt.self) { group in
            group.addTask {
                do {
                    try await operation()
                    return .succeeded
                } catch {
                    if let message = classify(error) { return .permanentFailure(message) }
                    return .queue
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .queue
            }
            let first = await group.next() ?? .queue
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Staged media files

extension OfflineQueue {
    /// A queued photo/video can't travel inside the `[String: String]`
    /// payload, and an absolute path can't either: the app container's UUID
    /// changes across reinstalls and OS migrations, so a path captured
    /// tonight may not resolve tomorrow. What IS stable is a file name
    /// relative to this directory, which is what the payload carries.
    static let mediaDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BarPassOfflineMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Copies an already-compressed file out of the temporary directory
    /// (which iOS may purge at any time) and into the queue's own
    /// directory. Returns the file name to put in the payload.
    static func stageMedia(_ fileURL: URL, fileExtension: String) throws -> String {
        let name = "\(UUID().uuidString).\(fileExtension)"
        try FileManager.default.copyItem(at: fileURL, to: mediaDirectory.appendingPathComponent(name))
        return name
    }
}

// MARK: - Dispatch

extension OfflineQueue {
    /// Wires each kind to the repository that actually performs it. Called
    /// once from BarPassApp.init — the queue itself deliberately knows no
    /// repositories.
    ///
    /// Throwing from a handler means "not done, try again later". Returning
    /// normally means "done, or never going to be done" — both drop the
    /// action, which is why the permanently-impossible cases below return
    /// instead of throwing: retrying an underage check-in on every
    /// reconnect for eight attempts would just burn battery.
    func installPerformHandlers() {
        perform = { action in
            switch action.kind {
            case .checkIn:
                guard let venueId = action.payload["venueId"] else { return }
                do {
                    _ = try await RepositoryDependencies.venueCheckin.checkIn(
                        venueId: venueId,
                        tripId: action.payload["tripId"]
                    )
                } catch let error as VenueCheckinError {
                    switch error {
                    case .birthdateRequired, .underage: return   // never fixable by a retry
                    case .network: throw error
                    }
                }
                // The button in the venue page reads this store; refresh it
                // so a check-in that landed while queued stops showing as
                // pending.
                await CheckInStore.shared.load()

            case .ageReport:
                guard let venueId = action.payload["venueId"],
                      let bracket = action.payload["bracket"] else { return }
                try await SupabaseAgeReportRepository().reportPerceivedAge(venueId: venueId, bracket: bracket)

            case .priceReport:
                guard let venueId = action.payload["venueId"],
                      let cents = action.payload["cents"].flatMap(Int.init) else { return }
                try await SupabasePriceReportRepository().reportDrinkPrice(venueId: venueId, cents: cents)

            case .venueMedia:
                guard let venueId = action.payload["venueId"],
                      let fileName = action.payload["fileName"],
                      let contentType = action.payload["contentType"],
                      let fileExtension = action.payload["fileExtension"],
                      let mediaType = action.payload["mediaType"].flatMap(VenueMediaType.init(rawValue:))
                else { return }
                let fileURL = Self.mediaDirectory.appendingPathComponent(fileName)
                // The file is gone (purged, or the user deleted app data).
                // There is nothing left to upload, so drop it rather than
                // retry a file that will never come back.
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
                _ = try await RepositoryDependencies.venueMedia.upload(
                    venueId: venueId,
                    fileURL: fileURL,
                    mediaType: mediaType,
                    contentType: contentType,
                    fileExtension: fileExtension,
                    progress: { _ in }
                )
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Strings

/// These three strings live here rather than in LocalizationService because
/// they belong to the queue and are used by every screen that feeds it.
enum OfflineQueueStrings {
    /// "subiendo…" — the action is saved locally and on its way.
    static func uploading(_ language: AppLanguage) -> String {
        switch language {
        case .es: return "Subiendo…"
        case .en: return "Uploading…"
        case .pt: return "Enviando…"
        }
    }

    /// Shown next to an action that is queued: no signal right now, but it
    /// is not lost.
    static func willSend(_ language: AppLanguage) -> String {
        switch language {
        case .es: return "Guardado. Se envía solo cuando vuelva la señal."
        case .en: return "Saved. It'll send itself when the signal is back."
        case .pt: return "Salvo. Será enviado quando o sinal voltar."
        }
    }

    /// The photo/video variant — it says explicitly that it is not on the
    /// venue page yet, because claiming otherwise would be false.
    static func mediaQueued(_ language: AppLanguage) -> String {
        switch language {
        case .es: return "Guardado. Se sube solo cuando vuelva la señal."
        case .en: return "Saved. It'll upload when the signal is back."
        case .pt: return "Salvo. Será enviado quando o sinal voltar."
        }
    }
}
