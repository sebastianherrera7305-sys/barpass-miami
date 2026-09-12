import Foundation
import Network
import UIKit

/// A paid pass must never be lost because LTE was bad for thirty seconds.
///
/// The sequence after a Skip the Line / table / ticket purchase is: the card
/// is charged (POST /transactions or /wallet/spend, which the user waits on),
/// and THEN the pass is minted server-side (POST /passes) so its QR code has
/// a record the door can redeem against. Until 2026-09-12 that second call
/// was fire-and-forget: it ignored the HTTP status, never retried, and
/// nothing remembered it. Inside a packed venue — exactly where passes are
/// bought — the charge would go through on the first good packet and the
/// registration would die on the next bad one. Money taken, no pass.
///
/// This outbox is the fix. Every registration is written to disk BEFORE its
/// first network attempt, and stays there until the server confirms it or
/// definitively rejects it. Retries happen with exponential backoff while the
/// app is open, immediately on reconnect (NWPathMonitor), on return to
/// foreground, and on the next launch. The server is idempotent on the
/// payment source (barpass-v2/src/app/api/passes/route.ts), so re-sending the
/// same registration N times yields the same single pass.
///
/// It is separate from `OfflineQueue` on purpose: that queue drops an action
/// after 8 failed attempts, which is right for a check-in and wrong for
/// something the user paid for. Here nothing is dropped — a registration
/// either succeeds, is rejected by the server (kept, shown to the user with
/// the payment reference so support can make it right), or outlives its own
/// validity window (also kept and shown, never silently deleted).
@MainActor
final class PassRegistrationOutbox: ObservableObject {
    static let shared = PassRegistrationOutbox()

    /// What a confirmation screen should show for one pass code.
    enum Status: Equatable {
        /// The server has the pass. Show the QR.
        case registered
        /// Paid; the server has not confirmed yet. Do NOT show a QR — it
        /// would not scan. `attempts` is how many tries have failed so far.
        case pending(attempts: Int, lastError: String?)
        /// Paid, and the server gave a definitive no (or the pass expired
        /// before it could be registered). `code` is the server's short
        /// error code; `reference` is the order / wallet transaction id.
        case failed(code: String, reference: String)

        var isRegistered: Bool { if case .registered = self { return true } else { return false } }
    }

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let registration: APIClient.PassRegistration
        let createdAt: Date
        var attempts: Int
        var lastError: String?
        /// Set once the server has definitively rejected this registration
        /// (or it expired unregistered). A terminal entry is never retried;
        /// it stays until the user dismisses it.
        var terminalCode: String?

        var isTerminal: Bool { terminalCode != nil }
        var passCode: String { registration.passCode }
    }

    /// Everything not yet confirmed: pending retries and terminal failures.
    /// Persisted. Pending entries are retried; terminal ones are displayed.
    @Published private(set) var entries: [Entry] = []

    /// Pass codes the server has confirmed during this process lifetime, so
    /// a confirmation screen that is still open flips to the QR the moment
    /// its registration lands. Not persisted: the server is the record.
    @Published private(set) var registeredCodes: Set<String> = []

    var pendingEntries: [Entry]  { entries.filter { !$0.isTerminal } }
    var failedEntries:  [Entry]  { entries.filter {  $0.isTerminal } }

    /// After the pass's own validity window (plus a grace period so a
    /// clock skew or a long night can't bite), registering it would not get
    /// anyone through a door. It is marked terminal — visible, with its
    /// payment reference — rather than deleted.
    private static let expiryGrace: TimeInterval = 12 * 3600

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("BarPassPassOutbox.json")
    }()

    private let monitor = NWPathMonitor()
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private var started = false

    private init() {
        entries = Self.read()
    }

    // MARK: - Lifecycle

    /// Call once at launch (AppDelegate.didFinishLaunching). Idempotent.
    /// Starts the reconnect watcher, the foreground hook, and flushes
    /// anything left over from a previous run.
    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "barpass.passoutbox.monitor"))

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }

        Task { await flush() }
    }

    // MARK: - Register

    /// Records the registration durably and starts the first attempt. Returns
    /// synchronously — the caller shows its confirmation screen right away,
    /// bound to `status(for:)`, which is `.pending` until the server answers.
    /// A pass is never `.registered` before the server has said so.
    func register(_ registration: APIClient.PassRegistration) {
        start()
        if registeredCodes.contains(registration.passCode) { return }
        if entries.contains(where: { $0.passCode == registration.passCode }) {
            Task { await flush() }
            return
        }
        entries.append(Entry(
            id: UUID(), registration: registration, createdAt: Date(),
            attempts: 0, lastError: nil, terminalCode: nil
        ))
        persist()
        Task { await flush() }
    }

    /// The truth for one pass code. `nil` means this outbox has never seen
    /// the code — callers must treat that as NOT registered.
    func status(for passCode: String) -> Status? {
        if registeredCodes.contains(passCode) { return .registered }
        guard let entry = entries.first(where: { $0.passCode == passCode }) else { return nil }
        if let code = entry.terminalCode {
            return .failed(code: code, reference: entry.registration.paymentSource.reference)
        }
        return .pending(attempts: entry.attempts, lastError: entry.lastError)
    }

    /// User-driven "try again now": cancels the backoff wait and flushes.
    func retryNow() {
        retryTask?.cancel()
        retryTask = nil
        Task { await flush() }
    }

    /// Removes a terminal (failed) entry once the user has seen it.
    /// Pending entries cannot be dismissed — they represent money paid.
    func dismissFailed(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].isTerminal else { return }
        entries.remove(at: i)
        persist()
    }

    // MARK: - Flush

    /// Safe to call as often as you like. Sends every pending entry, oldest
    /// first; the first retryable failure stops the pass (the link is bad,
    /// hammering the rest would only burn battery) and schedules a backoff.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        expireStale()

        let pending = pendingEntries.sorted { $0.createdAt < $1.createdAt }
        guard !pending.isEmpty else { return }

        guard let session = AuthService.shared.restoreSession() else {
            // Signed out with paid passes waiting. Keep them; they go out on
            // the next flush after sign-in.
            return
        }

        for entry in pending {
            do {
                let result = try await APIClient.registerPass(entry.registration, idToken: session.accessToken)
                registeredCodes.insert(result.passCode)
                registeredCodes.insert(entry.passCode)
                entries.removeAll { $0.id == entry.id }
                persist()
                BPHaptics.success()
            } catch let error as APIClient.PassRegistrationError {
                if error.isRetryable {
                    record(entry.id, error: error.errorDescription ?? "network")
                    scheduleRetry()
                    break
                } else {
                    markTerminal(entry.id, code: error.code ?? "rejected")
                }
            } catch {
                record(entry.id, error: error.localizedDescription)
                scheduleRetry()
                break
            }
        }
    }

    // MARK: - Backoff

    /// 5s, 10s, 20s, 40s, 80s, then every 2 minutes — driven by the most
    /// retried pending entry. Reconnect and foreground events cut the wait
    /// short via `retryNow()`/`flush()`.
    private func scheduleRetry() {
        retryTask?.cancel()
        let attempts = pendingEntries.map(\.attempts).max() ?? 1
        let delay = min(120.0, 5.0 * pow(2.0, Double(max(0, attempts - 1))))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: - Bookkeeping

    private func record(_ id: UUID, error: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].attempts += 1
        entries[i].lastError = error
        persist()
    }

    private func markTerminal(_ id: UUID, code: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].attempts += 1
        entries[i].terminalCode = code
        persist()
        BPHaptics.error()
    }

    private func expireStale() {
        var changed = false
        for i in entries.indices where !entries[i].isTerminal {
            if Date() > entries[i].registration.validUntil.addingTimeInterval(Self.expiryGrace) {
                entries[i].terminalCode = "expired_unregistered"
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Storage

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }
}
