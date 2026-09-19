import XCTest
@testable import BarPass_app

/// The seam between the radar and whatever carries discovery tokens between the
/// two phones. Exercised on the one path that never touches NearbyInteraction —
/// a phone that cannot range — so it runs on any simulator, with no UWB radio
/// and no second device.
final class ProximityRadarChannelTests: XCTestCase {

    @MainActor
    func test_phoneWithoutUWB_tellsTheOtherSideRatherThanLeavingThemWaiting() async {
        let channel = FakeChannel()
        let radar = ProximityRadar(channel: channel, capability: .cannotRange)
        radar.start()

        XCTAssertEqual(radar.state, .unsupported)
        await settle(until: { !channel.published.isEmpty })
        XCTAssertEqual(channel.published, [.cannotRange],
                       "silence would leave the other phone on 'waiting for them' forever")
    }

    @MainActor
    func test_peerLeavingOverTheChannelEndsTheRadar() async {
        let channel = FakeChannel()
        let radar = ProximityRadar(channel: channel, capability: .cannotRange)
        radar.start()
        await settle(until: { channel.isListening })

        channel.send(.peerLeft)
        await settle(until: { radar.state == .peerLeft })
        XCTAssertEqual(radar.state, .peerLeft)
    }

    /// Both the radar's tasks and this test run on the main actor, so yielding
    /// is enough to let them run — no sleeps, no wall-clock flakiness.
    @MainActor
    private func settle(until condition: () -> Bool, attempts: Int = 200) async {
        for _ in 0..<attempts where !condition() { await Task.yield() }
    }
}

/// Proves the transport protocol is implementable by a `@MainActor` type with
/// no NearbyInteraction import — which is exactly what piece 4 has to do.
@MainActor
private final class FakeChannel: ProximityTokenChannel {
    private(set) var published: [ProximityAnnouncement] = []
    private(set) var isClosed = false
    private var continuation: AsyncStream<ProximityPeerEvent>.Continuation?

    var isListening: Bool { continuation != nil }

    func publish(_ announcement: ProximityAnnouncement) async throws {
        published.append(announcement)
    }

    func events() async -> AsyncStream<ProximityPeerEvent> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func close() async {
        isClosed = true
        continuation?.finish()
        continuation = nil
    }

    func send(_ event: ProximityPeerEvent) {
        continuation?.yield(event)
    }
}
