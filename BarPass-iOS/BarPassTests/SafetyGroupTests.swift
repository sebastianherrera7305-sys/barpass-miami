import XCTest
@testable import BarPass_app

/// The rules of the "Radar → 30 ft handshake → leader beacon" state machine,
/// the magic link, and the ephemeral group — all pure, so they run on any
/// simulator with no network, no APNs, no UWB radio and no second phone.
final class SafetyGroupTests: XCTestCase {

    private let seekId = "6F1C0B8E-6C1A-4D0E-9D55-0C3F6F1C0B8E"
    private let groupId = "A2B4C6D8-1111-4222-8333-444455556666"

    // MARK: - HandshakeGate (state D: the 30 ft / 9.0 m line)

    func test_gate_isExactlyNineMetres_whichIsThirtyFeet() {
        XCTAssertEqual(HandshakeGate.thresholdMeters, 9.0)
        // 9.0 m is 29.5 ft: the spec's "30 ft" is this line, not a rounder one.
        XCTAssertEqual(Measurement(value: HandshakeGate.thresholdMeters, unit: UnitLength.meters)
            .converted(to: .feet).value, 29.53, accuracy: 0.01)
    }

    func test_gate_firesWhenCrossingBelowNineMetres() {
        var gate = HandshakeGate()
        XCTAssertFalse(gate.ingest(meters: 15))
        XCTAssertFalse(gate.ingest(meters: 9.0), "9.0 is NOT < 9.0")
        XCTAssertTrue(gate.ingest(meters: 8.99))
    }

    // UWB reports ~10 readings a second. Without "once per approach" the
    // leader's phone would buzz at full strength ten times a second at 8 m.
    func test_gate_firesOncePerApproach() {
        var gate = HandshakeGate()
        XCTAssertTrue(gate.ingest(meters: 8))
        for meters in [7.9, 6, 3, 1.4, 5, 8.5] {
            XCTAssertFalse(gate.ingest(meters: meters), "already inside at \(meters)")
        }
    }

    // A reading bouncing between 8.9 and 9.1 m must not re-fire on every bounce.
    func test_gate_hasHysteresis_soAJitteringReadingDoesNotRefire() {
        var gate = HandshakeGate()
        XCTAssertTrue(gate.ingest(meters: 8.9))
        XCTAssertFalse(gate.ingest(meters: 9.1))
        XCTAssertFalse(gate.ingest(meters: 8.9))
        XCTAssertFalse(gate.ingest(meters: 11.9), "still inside until 12 m")
        XCTAssertFalse(gate.ingest(meters: 8.9))
    }

    func test_gate_rearmsAfterWalkingAwayPastTwelveMetres() {
        var gate = HandshakeGate()
        XCTAssertTrue(gate.ingest(meters: 5))
        XCTAssertFalse(gate.ingest(meters: 12.0))
        XCTAssertTrue(gate.ingest(meters: 8), "a genuinely new approach fires again")
    }

    func test_gate_ignoresMissingAndNonsenseReadings() {
        var gate = HandshakeGate()
        XCTAssertFalse(gate.ingest(meters: nil))
        XCTAssertFalse(gate.ingest(meters: .nan))
        XCTAssertFalse(gate.ingest(meters: .infinity))
        XCTAssertFalse(gate.ingest(meters: -1))
        XCTAssertTrue(gate.ingest(meters: 4), "and none of that consumed or armed it")
    }

    func test_haptics_areBoundedNotEndless() {
        XCTAssertLessThanOrEqual(HandshakeHapticPattern.duration, 10)
        XCTAssertGreaterThan(HandshakeHapticPattern.pulseCount, 10, "aggressive, not a single tap")
        XCTAssertNotEqual(HandshakeHapticPattern.style(forPulse: 0), HandshakeHapticPattern.style(forPulse: 1))
    }

    // MARK: - Roles (only the leader lights the rally point)

    func test_onlyTheLeaderCanLightTheRallyPoint() {
        XCTAssertTrue(RadarRole.leader.canLightRallyPoint)
        XCTAssertFalse(RadarRole.seeker.canLightRallyPoint, "a seeker must never be able to light the rally point")
    }

    func test_onlyTheLeaderGetsTheHandshake() {
        XCTAssertTrue(RadarRole.leader.receivesHandshake)
        XCTAssertFalse(RadarRole.seeker.receivesHandshake)
    }

    func test_aSeek_isSeenAsLeaderByItsTargetAndSeekerByItsSeeker() {
        func seek(iAmTarget: Bool) -> SafetyGroupSeek {
            SafetyGroupSeek(seekId: seekId, groupId: groupId, seekerId: "s", seekerName: "Juan",
                            targetId: "l", targetName: "Sam", createdAt: Date(),
                            expiresAt: Date().addingTimeInterval(600), isLive: true, iAmTarget: iAmTarget)
        }
        XCTAssertEqual(seek(iAmTarget: true).role, .leader)
        XCTAssertEqual(seek(iAmTarget: false).role, .seeker)
        XCTAssertEqual(seek(iAmTarget: true).peerName, "Juan", "the leader's peer is whoever is looking")
        XCTAssertEqual(seek(iAmTarget: false).peerName, "Sam", "the seeker's peer is the leader")
    }

    // MARK: - ProximityRadarManager.phase(for:)

    @MainActor
    func test_phase_followsTheRadarState() {
        typealias M = ProximityRadarManager
        XCTAssertEqual(M.phase(for: .idle, current: .idle), .idle)
        XCTAssertEqual(M.phase(for: .waitingForPeer, current: .idle), .connecting)
        XCTAssertEqual(M.phase(for: .acquiring, current: .connecting), .connecting)
        XCTAssertEqual(M.phase(for: .distanceOnly(meters: 20, trend: .closer), current: .connecting), .ranging)
        XCTAssertEqual(M.phase(for: .peerLeft, current: .ranging), .ended)
        XCTAssertEqual(M.phase(for: .unsupported, current: .connecting), .ended)
        XCTAssertEqual(M.phase(for: .failed(.sessionFailed), current: .ranging), .ended)
    }

    // Getting to 3 m must not "undo" having crossed 9 m.
    @MainActor
    func test_phase_handshakeSurvivesLaterReadings_butNotTheEndOfTheRadar() {
        typealias M = ProximityRadarManager
        XCTAssertEqual(M.phase(for: .distanceOnly(meters: 3, trend: .closer), current: .handshake), .handshake)
        XCTAssertEqual(M.phase(for: .signalLost(lastMeters: 3, at: Date()), current: .handshake), .handshake)
        XCTAssertEqual(M.phase(for: .peerLeft, current: .handshake), .ended)
    }

    // MARK: - The manager end to end, with no radio

    @MainActor
    private func manager(role: RadarRole) -> ProximityRadarManager {
        ProximityRadarManager(role: role, channel: NullSeekChannel(), radar: nil)
    }

    @MainActor
    func test_leader_crossingNineMetres_showsTheBanner() {
        let m = manager(role: .leader)
        m.ingest(.distanceOnly(meters: 20, trend: .closer))
        XCTAssertFalse(m.showsHandshakeBanner)
        m.ingest(.distanceOnly(meters: 8.5, trend: .closer))
        XCTAssertEqual(m.phase, .handshake)
        XCTAssertTrue(m.showsHandshakeBanner)
    }

    // The seeker learns they're close, but never gets the banner (the button
    // that lights the rally point).
    @MainActor
    func test_seeker_crossingNineMetres_neverGetsTheBanner() {
        let m = manager(role: .seeker)
        m.ingest(.distanceOnly(meters: 8.5, trend: .closer))
        XCTAssertEqual(m.phase, .handshake)
        XCTAssertFalse(m.showsHandshakeBanner)
    }

    @MainActor
    func test_dismissingTheBanner_doesNotRefireUntilTheyWalkAwayAndReturn() {
        let m = manager(role: .leader)
        m.ingest(.distanceOnly(meters: 8, trend: .closer))
        m.dismissBanner()
        m.ingest(.distanceOnly(meters: 6, trend: .closer))
        XCTAssertFalse(m.showsHandshakeBanner)
        m.ingest(.distanceOnly(meters: 13, trend: .farther))
        m.ingest(.distanceOnly(meters: 8, trend: .closer))
        XCTAssertTrue(m.showsHandshakeBanner)
    }

    @MainActor
    func test_manualRallyPoint_isOfferedOnlyToTheLeader_andOnlyWhenRangingIsImpossible() {
        let leader = manager(role: .leader)
        XCTAssertFalse(leader.needsManualRallyPoint)
        leader.ingest(.unsupported)
        XCTAssertTrue(leader.needsManualRallyPoint, "an iPhone SE would otherwise be stuck on a radar that cannot advance")

        let seeker = manager(role: .seeker)
        seeker.ingest(.unsupported)
        XCTAssertFalse(seeker.needsManualRallyPoint, "a seeker never gets a way to light the rally point, even a fallback one")
    }

    // MARK: - SafetyPushPayload

    func test_seekPayload_parsesItsIds() throws {
        let payload = try XCTUnwrap(SafetyPushPayload.parse([
            "alert_type": "seek_leader", "seek_id": seekId, "group_id": groupId,
            "expires_at": "2026-09-20T02:00:00Z"]))
        guard case .seekLeader(let id, let expires) = payload.kind else { return XCTFail("wrong kind") }
        XCTAssertEqual(id, seekId)
        XCTAssertNotNil(expires)
        XCTAssertEqual(payload.groupId, groupId)
    }

    // A seek with no verifiable id must not open anything, so it must not
    // parse at all rather than parse "partially".
    func test_seekWithoutAValidId_isRejected() {
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": "seek_leader"]))
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": "seek_leader", "seek_id": "not-a-uuid"]))
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": "seek_leader", "seek_id": ""]))
    }

    // The retired panic-button payload must not still be honoured.
    func test_theOldRaiseHandPayload_isNoLongerASafetyPush() {
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": "raise_hand", "alert_id": seekId]))
    }

    func test_silentRefresh_carriesNoSeekId() throws {
        let payload = try XCTUnwrap(SafetyPushPayload.parse(["alert_type": "group_refresh", "group_id": groupId]))
        XCTAssertEqual(payload.kind, .groupRefresh)
    }

    func test_otherPushes_areNotSafetyPushes() {
        XCTAssertNil(SafetyPushPayload.parse([:]))
        XCTAssertNil(SafetyPushPayload.parse(["deep_link": "barpass://trip/1"]))
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": "something_else"]))
        XCTAssertNil(SafetyPushPayload.parse(["alert_type": 7]))
    }

    func test_expiredSeek_isStale_andAFutureOneIsNot() {
        let now = Date()
        XCTAssertTrue(SafetyPushPayload.isStale(expiresAt: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(SafetyPushPayload.isStale(expiresAt: now, now: now))
        XCTAssertFalse(SafetyPushPayload.isStale(expiresAt: now.addingTimeInterval(60), now: now))
        XCTAssertFalse(SafetyPushPayload.isStale(expiresAt: nil), "unknown, not 'stale' and not 'forever'")
    }

    // MARK: - Magic link

    func test_magicLink_isTheShapeTheRouterReads() throws {
        let link = SafetyGroupFormat.magicLink(groupId: groupId)
        XCTAssertEqual(link, "barpass://group?id=\(groupId)")
        let route = DeepLinkRouter.parse(try XCTUnwrap(URL(string: link)))
        XCTAssertEqual(route, .group(id: groupId))
    }

    func test_magicLink_carriesNothingButTheGroupId() {
        let link = SafetyGroupFormat.magicLink(groupId: groupId)
        XCTAssertEqual(URLComponents(string: link)?.queryItems?.map(\.name), ["id"])
    }

    func test_shareMessage_putsTheLinkFirstAndTheCodeAsBackup() {
        let text = SafetyGroupFormat.shareMessage(template: "Join: %@ (code %@)", groupId: groupId, code: "ABC234")
        XCTAssertEqual(text, "Join: barpass://group?id=\(groupId) (code ABC234)")
    }

    func test_deepLink_groupRoute() {
        func route(_ s: String) -> DeepLinkRoute? { DeepLinkRouter.parse(URL(string: s)!) }
        XCTAssertEqual(route("barpass://group?id=\(groupId)"), .group(id: groupId))
        XCTAssertEqual(route("BARPASS://group?id=\(groupId)"), .group(id: groupId), "scheme and host are case-insensitive")
        // Not a link we can act on: never a half-parsed route.
        XCTAssertNil(route("barpass://group"))
        XCTAssertNil(route("barpass://group?id="))
        XCTAssertNil(route("barpass://group?id=not-a-uuid"))
        XCTAssertNil(route("barpass://group?code=\(groupId)"))
        XCTAssertNil(route("https://evil.example/group?id=\(groupId)"))
    }

    // MARK: - Whose light is on (BeaconFlares.Owner)

    // The rally point must survive the OWN-beacon (auxilio) poll, and the own-beacon
    // poll must still be able to turn its own light off — without either store
    // having to look at the other one.
    func test_ownBeaconPoll_cannotSwitchOffTheRallyPointsLight() {
        XCTAssertFalse(BeaconFlares.shouldStop(holder: .rally, requester: .mine))
    }

    func test_ownBeaconPoll_stillSwitchesOffItsOwnLight() {
        XCTAssertTrue(BeaconFlares.shouldStop(holder: .mine, requester: .mine),
                      "the 'it turns off even if nobody is looking' guarantee must survive for the own beacon")
    }

    func test_theRallyPointScreenCannotSwitchOffTheOwnBeacon() {
        XCTAssertFalse(BeaconFlares.shouldStop(holder: .mine, requester: .rally))
        XCTAssertTrue(BeaconFlares.shouldStop(holder: .rally, requester: .rally))
    }

    // Sign-out and deinit have no owner to name: they must always be able to stop it.
    func test_aForcedStop_stopsWhoeverHoldsTheLight() {
        XCTAssertTrue(BeaconFlares.shouldStop(holder: .mine, requester: nil))
        XCTAssertTrue(BeaconFlares.shouldStop(holder: .rally, requester: nil))
    }

    func test_stoppingWhenNobodyHoldsTheLight_isHarmless() {
        XCTAssertTrue(BeaconFlares.shouldStop(holder: nil, requester: .mine))
        XCTAssertTrue(BeaconFlares.shouldStop(holder: nil, requester: .rally))
        XCTAssertTrue(BeaconFlares.shouldStop(holder: nil, requester: nil))
    }

    // MARK: - Auxilio vs. punto de encuentro: two signals, two identities

    // The whole point of splitting them is that nobody mistakes "estamos acá"
    // (the leader's rally point) for "estoy acá, vengan" (the auxilio faro) in a
    // dark room. The auxilio can produce any (color, rhythm) that
    // `BeaconIdentity.rhythm(in:)` yields across the four variants — the rally
    // point must be none of them. If this fails after changing
    // `RallyPointIdentity`, the new pair collides with an auxilio signal.
    func test_rallyPoint_isNotAnyAuxilioSignal() throws {
        for identity in BeaconIdentity.allCases {
            for index in 0 ..< BeaconVariant.count {
                let variant = try XCTUnwrap(BeaconVariant(serverIndex: index))
                let auxilio = identity.rhythm(in: variant)
                let collides = identity == RallyPointIdentity.identity && auxilio == RallyPointIdentity.rhythm
                XCTAssertFalse(collides,
                               "the rally point (\(RallyPointIdentity.identity), \(RallyPointIdentity.rhythm.id)) equals the auxilio signal (\(identity), \(auxilio.id)) in variant \(index)")
            }
        }
    }

    // The rally point still has to obey the same safety limits as any beacon
    // rhythm: at most 3 flashes/second (WCAG 2.3.1) and no dark phase shorter
    // than the torch layer's 180 ms floor.
    func test_rallyPoint_rhythmRespectsPhotosensitivityLimits() {
        XCTAssertLessThanOrEqual(RallyPointIdentity.rhythm.maxFlashesPerSecond, 3)
        let darkPhases = RallyPointIdentity.rhythm.phases.filter { !$0.isLit }
        XCTAssertTrue(darkPhases.allSatisfy { $0.milliseconds >= 180 })
    }

    // MARK: - Push delivery: "accepted" is not "delivered"

    // A 200 from APNs means accepted for delivery. The state's name must not
    // read as more than that, and the user-facing string must not either.
    func test_apnsAcceptance_isNamedAcceptedNotSentOrDelivered() {
        let state = SafetyPushClient.delivery(status: 200, body: ["recipients": 1, "sent": 1, "failed": 0])
        XCTAssertEqual(state, .accepted(recipients: 1))
        XCTAssertEqual(L10n.t("safetyGroup.delivery.accepted", language: .es), "Mandamos el aviso al líder.")
        XCTAssertFalse(L10n.t("safetyGroup.delivery.accepted", language: .en).lowercased().contains("alerted"),
                       "'alerted' claims the leader was reached; APNs only accepted it")
    }

    // MARK: - Push delivery mapping

    func test_delivery_mapsTheRoutesAnswersToWhatTheScreenSays() {
        XCTAssertEqual(SafetyPushClient.delivery(status: 200, body: ["recipients": 1, "sent": 1, "failed": 0]), .accepted(recipients: 1))
        XCTAssertEqual(SafetyPushClient.delivery(status: 503, body: ["error": "push_not_configured"]), .unavailable)
        // The leader has not registered a phone: not a failure, just not deliverable.
        XCTAssertEqual(SafetyPushClient.delivery(status: 200, body: ["recipients": 0, "sent": 0, "failed": 0]), .unavailable)
        XCTAssertEqual(SafetyPushClient.delivery(status: 200, body: ["recipients": 1, "sent": 0, "failed": 1]), .failed)
        XCTAssertEqual(SafetyPushClient.delivery(status: 429, body: [:]), .failed)
        XCTAssertEqual(SafetyPushClient.delivery(status: 500, body: [:]), .failed)
    }

    // MARK: - Device token

    func test_deviceTokenHex_matchesWhatAppDelegatePosts() {
        XCTAssertEqual(DeviceTokenFormat.hex(Data([0x00, 0x0f, 0xa0, 0xff])), "000fa0ff")
    }

    func test_implausibleTokens_areNotUploaded() {
        XCTAssertFalse(DeviceTokenFormat.isPlausible(""))
        XCTAssertFalse(DeviceTokenFormat.isPlausible(String(repeating: "a", count: 31)))
        XCTAssertTrue(DeviceTokenFormat.isPlausible(String(repeating: "a", count: 64)))
        XCTAssertFalse(DeviceTokenFormat.isPlausible(String(repeating: "a", count: 201)))
    }

    // MARK: - Errors

    func test_serverErrorNames_mapToTheirOwnCase() {
        XCTAssertEqual(SafetyGroupError.from(responseBody: #"{"message":"group_full"}"#), .groupFull)
        XCTAssertEqual(SafetyGroupError.from(responseBody: #"{"message":"not_target"}"#), .notTarget)
        XCTAssertEqual(SafetyGroupError.from(responseBody: #"{"message":"seek_not_found"}"#), .seekNotFound)
        XCTAssertEqual(SafetyGroupError.from(responseBody: #"{"message":"is_leader"}"#), .isLeader)
        XCTAssertEqual(SafetyGroupError.from(responseBody: #"{"message":"already_in_group"}"#), .alreadyInGroup)
        XCTAssertEqual(SafetyGroupError.from(responseBody: "??"), .unknown)
    }

    // The raw value IS the l10n key suffix, so a case with no string behind
    // it would show the raw key to a user. This walks every case. Note the
    // lookup falls back to Spanish before the key, so this catches a case
    // missing from ALL tables, not one missing from a single translation.
    func test_everyErrorCase_resolvesToARealString() {
        let cases: [SafetyGroupError] = [
            .notAuthenticated, .alreadyInGroup, .groupNotFound, .groupFull, .notLeader, .notInGroup,
            .notInTrip, .isLeader, .noLeader, .seekNotFound, .notTarget,
            .rateLimited, .messageLength, .chatKeyUnavailable, .network, .unknown]
        for language in AppLanguage.allCases {
            for error in cases {
                let key = "safetyGroup.error.\(error.rawValue)"
                XCTAssertNotEqual(L10n.t(key, language: language), key, "\(key) missing in \(language)")
            }
        }
    }

    // MARK: - Message merge

    private func message(_ id: String, _ seconds: TimeInterval) -> SafetyGroupMessage {
        SafetyGroupMessage(id: id, senderId: "u", senderName: "U", text: id,
                           createdAt: Date(timeIntervalSince1970: seconds))
    }

    // `since` is truncated to milliseconds while Postgres keeps microseconds,
    // so the newest message comes back again on the next poll.
    func test_merge_doesNotDuplicateTheMessageThePollReturnsAgain() {
        let existing = [message("a", 1), message("b", 2)]
        let merged = SafetyGroupMessageMerge.merge(existing: existing, incoming: [message("b", 2), message("c", 3)], cap: 500)
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }

    func test_merge_keepsChronologicalOrderEvenIfTheyArriveOutOfOrder() {
        let merged = SafetyGroupMessageMerge.merge(existing: [message("b", 2)], incoming: [message("a", 1), message("c", 3)], cap: 500)
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }

    func test_merge_capsToTheNewestMessages() {
        let many = (1...10).map { message("m\($0)", TimeInterval($0)) }
        let merged = SafetyGroupMessageMerge.merge(existing: [], incoming: many, cap: 3)
        XCTAssertEqual(merged.map(\.id), ["m8", "m9", "m10"])
    }

    // MARK: - Chat rules

    func test_chatRules_matchTheServer() {
        XCTAssertFalse(SafetyGroupChatRules.canSend(""))
        XCTAssertFalse(SafetyGroupChatRules.canSend("   \n "))
        XCTAssertTrue(SafetyGroupChatRules.canSend("hola"))
        XCTAssertTrue(SafetyGroupChatRules.canSend(String(repeating: "a", count: 500)))
        XCTAssertFalse(SafetyGroupChatRules.canSend(String(repeating: "a", count: 501)))
    }

    // MARK: - Group TTL and code formatting

    @MainActor
    func test_defaultTTL_isFourHours() {
        XCTAssertEqual(SafetyGroupStore.defaultHours, 4)
    }

    func test_remaining_roundsDown_andNeverMakesTheNightLonger() {
        XCTAssertEqual(SafetyGroupFormat.remaining(-5), .lessThanAMinute)
        XCTAssertEqual(SafetyGroupFormat.remaining(59), .lessThanAMinute)
        XCTAssertEqual(SafetyGroupFormat.remaining(60), .minutes(1))
        XCTAssertEqual(SafetyGroupFormat.remaining(59 * 60 + 30), .minutes(59))
        XCTAssertEqual(SafetyGroupFormat.remaining(3600), .hoursMinutes(1, 0))
        XCTAssertEqual(SafetyGroupFormat.remaining(4 * 3600 + 125), .hoursMinutes(4, 2))
    }

    func test_codeNormalization_forgivesCaseSpacesAndDashes() {
        XCTAssertEqual(SafetyGroupFormat.normalizedCode(" ab-c 2d3x "), "ABC2D3")
        XCTAssertTrue(SafetyGroupFormat.isCompleteCode("abc2d3"))
        XCTAssertFalse(SafetyGroupFormat.isCompleteCode("abc2"))
    }

    func test_pushEnvironment_isSandboxForDebugBuilds() {
        #if DEBUG
        XCTAssertEqual(PushEnvironment.current, "sandbox")
        #else
        XCTAssertEqual(PushEnvironment.current, "production")
        #endif
    }
}

/// A token channel that never says anything: enough to construct a manager and
/// drive it with `ingest(_:)`, with no NearbyInteraction and no network.
private struct NullSeekChannel: ProximityTokenChannel {
    func publish(_ announcement: ProximityAnnouncement) async throws {}
    func events() async -> AsyncStream<ProximityPeerEvent> { AsyncStream { $0.finish() } }
    func close() async {}
}
