import Foundation

/// The seam `ProximityRadarState.swift` marks "implemented by piece 4":
/// carries one phone's NearbyInteraction discovery token to the other
/// through the beacon's token mailbox (supabase/safety_beacon.sql).
///
/// It POLLS, because this app has no push. The token is a few hundred
/// bytes and only has to cross once, so a 3s poll for the seconds before
/// ranging starts is cheap and finishes fast; once `.token` is delivered,
/// NearbyInteraction is phone-to-phone and this channel stops mattering.
///
/// Isolation: an `actor`, so the poll loop and `close()` cannot race on
/// the continuation. It touches no UIKit and no @MainActor state at all —
/// deliberately, since builds 22/26/50 all died on a callback reaching
/// main-actor state from a background queue.
final actor SafetyBeaconTokenChannel: ProximityTokenChannel {

    /// Whose token we are waiting for. A beacon can have several people
    /// walking over, but a ranging session is 1:1, so the peer is named
    /// when the channel is opened.
    private let peerUserId: String
    private let beaconId: String
    private let repository: SafetyBeaconRepository

    private var pump: Task<Void, Never>?
    private var continuation: AsyncStream<ProximityPeerEvent>.Continuation?
    private var lastDeliveredToken: String?
    private var announcedPeerCannotRange = false
    private var consecutiveFailures = 0
    /// Our own last announcement, re-sent on a heartbeat so the far side's
    /// `token_updated_at` keeps meaning something.
    private var myAnnouncement: ProximityAnnouncement?
    private var isClosed = false

    /// Fast while the two people are walking toward each other — this is
    /// the only window where latency is felt. It stops on its own as soon
    /// as the peer's token has been handed over.
    private static let pollInterval: Duration = .seconds(3)
    /// Re-publish our own token this often while the session lives.
    private static let heartbeat: Duration = .seconds(45)
    /// Only after several consecutive failures, so one dropped request in a
    /// basement does not report a dead channel.
    private static let failuresBeforeChannelFailed = 4

    init(beaconId: String,
         peerUserId: String,
         repository: SafetyBeaconRepository = SupabaseSafetyBeaconRepository()) {
        self.beaconId = beaconId
        self.peerUserId = peerUserId
        self.repository = repository
    }

    // MARK: - ProximityTokenChannel

    func publish(_ announcement: ProximityAnnouncement) async throws {
        myAnnouncement = announcement
        try await send(announcement)
    }

    func events() -> AsyncStream<ProximityPeerEvent> {
        AsyncStream { continuation in
            // The Task inherits this actor's isolation, so `attach` runs on
            // the actor and the continuation is only ever touched there.
            Task { self.attach(continuation) }
        }
    }

    func close() async {
        isClosed = true
        pump?.cancel()
        pump = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Internals

    private func send(_ announcement: ProximityAnnouncement) async throws {
        switch announcement {
        case .token(let data):
            try await repository.publishToken(data.base64EncodedString(),
                                              canRange: true, beaconId: beaconId)
        case .cannotRange:
            // Published as a fact, not as silence: the far side must be
            // told to stop waiting for a token and look for the colour.
            try await repository.publishToken(nil, canRange: false, beaconId: beaconId)
        }
    }

    private func attach(_ continuation: AsyncStream<ProximityPeerEvent>.Continuation) {
        guard !isClosed else { continuation.finish(); return }
        self.continuation = continuation
        guard pump == nil else { return }
        pump = Task { [weak self] in
            var sinceHeartbeat: Duration = .zero
            while !Task.isCancelled {
                await self?.poll()
                sinceHeartbeat += Self.pollInterval
                if sinceHeartbeat >= Self.heartbeat {
                    sinceHeartbeat = .zero
                    await self?.reannounce()
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    /// Best-effort: a failed heartbeat is already counted by `poll()`, and
    /// failing to re-publish a token the peer already holds breaks nothing.
    private func reannounce() async {
        guard let myAnnouncement else { return }
        try? await send(myAnnouncement)
    }

    private func poll() async {
        do {
            let peers = try await repository.peerTokens(beaconId: beaconId)
            consecutiveFailures = 0
            guard let peer = peers.first(where: { $0.userId == peerUserId }) else { return }

            if !peer.canRange, !announcedPeerCannotRange {
                announcedPeerCannotRange = true
                continuation?.yield(.peerCannotRange)
                return
            }
            // A DIFFERENT token is a reconnection, not a duplicate: the peer
            // restarted its NISession and the old token is dead. Piece 3
            // handles that, so forward it instead of deduping it away.
            guard let raw = peer.discoveryToken, raw != lastDeliveredToken,
                  let data = Data(base64Encoded: raw) else { return }
            lastDeliveredToken = raw
            announcedPeerCannotRange = false
            continuation?.yield(.token(data))

        } catch SafetyBeaconError.notFound {
            // The beacon is resolved or expired — a FACT that the session is
            // over, which is why get_beacon_tokens raises instead of
            // returning zero rows (zero rows means "nobody published yet",
            // the opposite instruction to the caller).
            continuation?.yield(.peerLeft)
            await close()

        } catch {
            // Deliberately NOT .peerLeft. We can no longer learn anything
            // NEW about them, which is not the same as them being gone —
            // and NearbyInteraction keeps ranging phone-to-phone with no
            // network at all, so a dead channel does not end the session.
            consecutiveFailures += 1
            if consecutiveFailures == Self.failuresBeforeChannelFailed {
                continuation?.yield(.channelFailed(error))
            }
        }
    }
}
