import XCTest
@testable import BarPass_app

/// The beacon's whole promise is that four phones held up in a dark, loud
/// room resolve to four people, with no server, no pairing and no retry. Every
/// test here defends one half of that: the assignment cannot drift between
/// devices, and no two people in a group can end up looking alike.
final class BeaconIdentityTests: XCTestCase {

    private let group = ["ana", "beto", "caro", "dani"]

    // MARK: - Stability

    func test_assignment_isIdenticalUnderEveryReordering() {
        // A group list arrives from a different query, a different sort, a
        // different join order on every phone. If order leaked into the
        // result, two friends would disagree about who is gold — and only in
        // the field, never on a desk.
        let expected = BeaconIdentity.assign(memberIds: group, groupId: "trip-777")
        for ordering in permutations(group) {
            XCTAssertEqual(BeaconIdentity.assign(memberIds: ordering, groupId: "trip-777"), expected)
        }
    }

    func test_assignment_isIdenticalUnderEveryReordering_whenOverflowing() {
        let big = ["ana", "beto", "caro", "dani", "eze", "fran"]
        let expected = BeaconIdentity.assign(memberIds: big, groupId: "trip-999")
        for ordering in permutations(big) {
            XCTAssertEqual(BeaconIdentity.assign(memberIds: ordering, groupId: "trip-999"), expected)
        }
    }

    func test_assignment_isPinnedToExactValues() {
        // Pins the algorithm itself. Any change here means two app versions
        // in the same group hand out different colours — a silent, in-person
        // failure that no other test in the suite would catch.
        let result = BeaconIdentity.assign(memberIds: group, groupId: "trip-777")
        XCTAssertEqual(result.assigned, ["caro": .gold, "beto": .cyan, "dani": .green, "ana": .magenta])
    }

    func test_hash_matchesPublishedFNV1aVectors() {
        // Swift's own Hasher is seeded per process; these are the published
        // FNV-1a 64 vectors, so the hash is the same on every device forever.
        XCTAssertEqual(BeaconIdentity.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(BeaconIdentity.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(BeaconIdentity.fnv1a64("foobar"), 0x8594_4171_f739_67e8)
    }

    func test_rank_separatesGroupIdFromMemberId() {
        // Without the separator, ("ab","c") and ("a","bc") would hash alike.
        XCTAssertNotEqual(
            BeaconIdentity.rank(memberId: "c", groupId: "ab"),
            BeaconIdentity.rank(memberId: "bc", groupId: "a")
        )
    }

    // MARK: - No two people look alike

    func test_noTwoMembers_shareAColourOrARhythm() {
        for groupId in ["trip-777", "trip-888", "trip-999", "", "🎉"] {
            let assigned = BeaconIdentity.assign(memberIds: group, groupId: groupId).assigned
            XCTAssertEqual(assigned.count, 4)
            XCTAssertEqual(Set(assigned.values.map(\.beaconColor)).count, 4, groupId)
            XCTAssertEqual(Set(assigned.values.map(\.rhythm)).count, 4, groupId)
        }
    }

    func test_palette_hasFourDistinctColoursAndFourDistinctRhythms() {
        XCTAssertEqual(BeaconIdentity.allCases.count, 4)
        XCTAssertEqual(Set(BeaconIdentity.allCases.map(\.beaconColor)).count, 4)
        XCTAssertEqual(Set(BeaconIdentity.allCases.map(\.rhythm)).count, 4)
    }

    func test_pairOfTwo_alwaysGetsTheColourBlindSafePair() {
        // Gold and cyan sit at the two ends of the blue-yellow axis, the only
        // axis a dichromat keeps. Two-person groups are the common case, so
        // the palette is ordered to hand out that pair first.
        for members in [["ana", "beto"], ["zed", "abe"], ["x", "y"]] {
            let assigned = BeaconIdentity.assign(memberIds: members, groupId: "g").assigned
            XCTAssertEqual(Set(assigned.values), [.gold, .cyan])
        }
    }

    func test_colourBlindCollapsePairs_carryVeryDifferentRhythms() {
        // gold/green collapse for a deuteranope: separated by rate (4x period).
        XCTAssertNotEqual(BeaconIdentity.gold.rhythm, BeaconIdentity.green.rhythm)
        let slow = Double(BeaconIdentity.green.rhythm.periodMilliseconds)
        let fast = Double(BeaconIdentity.gold.rhythm.periodMilliseconds)
        XCTAssertGreaterThan(slow / fast, 3)
        // cyan/magenta collapse for a protanope: one blinks, one never does.
        XCTAssertGreaterThan(BeaconIdentity.cyan.rhythm.maxFlashesPerSecond, 0)
        XCTAssertEqual(BeaconIdentity.magenta.rhythm.maxFlashesPerSecond, 0)
    }

    // MARK: - Same person, different groups

    func test_sameMember_mayGetDifferentColoursInDifferentGroups() {
        // Intended: the identity belongs to (person, group), not to the person.
        // Nothing is wrong when Ana is magenta with one crew and gold with
        // another — only collisions *inside* one group matter.
        let a = BeaconIdentity.assign(memberIds: group, groupId: "trip-777")
        let b = BeaconIdentity.assign(memberIds: group, groupId: "trip-888")
        XCTAssertEqual(a.identity(for: "ana"), .magenta)
        XCTAssertEqual(b.identity(for: "ana"), .gold)
        // ...and each group is still internally collision-free.
        XCTAssertEqual(Set(b.assigned.values).count, 4)
    }

    // MARK: - More than four

    func test_moreThanFour_leavesTheExtrasWithoutASignal() {
        // Documented behaviour: four is the whole palette. A fifth person is
        // reported as having no signal, never given a duplicate colour.
        let result = BeaconIdentity.assign(
            memberIds: ["ana", "beto", "caro", "dani", "eze", "fran"], groupId: "trip-999")
        XCTAssertEqual(result.assigned.count, 4)
        XCTAssertEqual(result.withoutSignal, ["eze", "ana"])
        XCTAssertFalse(result.coversWholeGroup)
        XCTAssertEqual(result.lookup("eze"), .noSignalAvailable)
        XCTAssertEqual(result.lookup("dani"), .assigned(.gold))
        XCTAssertNil(result.identity(for: "ana"))
        XCTAssertEqual(Set(result.assigned.values).count, 4)
    }

    func test_lookup_distinguishesNoSignalFromUnknownPerson() {
        let result = BeaconIdentity.assign(memberIds: group, groupId: "trip-777")
        XCTAssertEqual(result.lookup("nadie"), .notInGroup)
        XCTAssertTrue(result.coversWholeGroup)
    }

    func test_duplicateIds_collapseToOnePerson() {
        let result = BeaconIdentity.assign(memberIds: ["ana", "ana", "ana", "beto"], groupId: "g")
        XCTAssertEqual(result.assigned.count, 2)
        XCTAssertTrue(result.withoutSignal.isEmpty)
    }

    func test_emptyGroup_producesNothingRatherThanADefault() {
        let result = BeaconIdentity.assign(memberIds: [], groupId: "g")
        XCTAssertTrue(result.assigned.isEmpty)
        XCTAssertTrue(result.withoutSignal.isEmpty)
        XCTAssertEqual(result.lookup("ana"), .notInGroup)
    }

    // MARK: - Rhythm is a spec the screen and the torch can both follow

    func test_everyRhythm_staysWithinTheThreeFlashPerSecondLimit() {
        // WCAG 2.3.1. A full-screen saturated strobe is not exempt by area,
        // and a safety feature must not trigger a photosensitive seizure.
        for rhythm in BeaconRhythm.all {
            XCTAssertLessThanOrEqual(rhythm.maxFlashesPerSecond, 3, rhythm.id)
        }
        XCTAssertEqual(BeaconRhythm.fastFlicker.maxFlashesPerSecond, 3)
        XCTAssertEqual(BeaconRhythm.doubleBlink.maxFlashesPerSecond, 2)
        XCTAssertEqual(BeaconRhythm.slowBlink.maxFlashesPerSecond, 1)
    }

    func test_everyRhythm_completesACycleInsideOneGlance() {
        for rhythm in BeaconRhythm.all {
            XCTAssertLessThanOrEqual(rhythm.periodMilliseconds, 1500, rhythm.id)
            XCTAssertGreaterThan(rhythm.periodMilliseconds, 0, rhythm.id)
        }
    }

    func test_blinkingRhythms_surviveTheTorchLayersMinimumStep() {
        // BeaconFlareTypes clamps any step under 180ms and reports
        // `wasClamped`. A clamped torch runs a pattern the screen is not
        // running — the exact drift this rhythm spec exists to prevent — so
        // no phase here may sit under that floor.
        for rhythm in BeaconRhythm.all where !rhythm.isContinuous {
            for phase in rhythm.phases {
                XCTAssertGreaterThanOrEqual(phase.milliseconds, 180, rhythm.id)
            }
        }
    }

    func test_onlySolid_isContinuous() {
        // The torch layer cannot express a continuous beam as a pattern (it
        // appends an OFF phase), so a bridge must branch on this flag.
        XCTAssertTrue(BeaconRhythm.solid.isContinuous)
        for rhythm in [BeaconRhythm.fastFlicker, .slowBlink, .doubleBlink] {
            XCTAssertFalse(rhythm.isContinuous, rhythm.id)
        }
    }

    func test_isLit_followsPhaseBoundariesExactly() {
        // Screen and torch both read this function against one shared start
        // instant; if it were not exact they would drift into a fifth rhythm.
        let flicker = BeaconRhythm.fastFlicker
        XCTAssertTrue(flicker.isLit(atMillisecondsSinceStart: 0))
        XCTAssertTrue(flicker.isLit(atMillisecondsSinceStart: 179))
        XCTAssertFalse(flicker.isLit(atMillisecondsSinceStart: 180))
        XCTAssertFalse(flicker.isLit(atMillisecondsSinceStart: 359))
        XCTAssertTrue(flicker.isLit(atMillisecondsSinceStart: 360))

        let double = BeaconRhythm.doubleBlink
        XCTAssertTrue(double.isLit(atMillisecondsSinceStart: 179))
        XCTAssertFalse(double.isLit(atMillisecondsSinceStart: 180))
        XCTAssertTrue(double.isLit(atMillisecondsSinceStart: 360))
        XCTAssertFalse(double.isLit(atMillisecondsSinceStart: 540))
        XCTAssertTrue(double.isLit(atMillisecondsSinceStart: 1300))
    }

    func test_solid_isNeverDark() {
        for ms in [0, 1, 999, 1000, 100_000] {
            XCTAssertTrue(BeaconRhythm.solid.isLit(atMillisecondsSinceStart: ms))
        }
        XCTAssertEqual(BeaconRhythm.solid.dutyCycle, 1, accuracy: 0.0001)
    }

    func test_isLit_neverGoesDarkOnDegenerateElapsedValues() {
        // A beacon that blacks out because of NaN or an overflow is a beacon
        // that failed at the only moment it mattered.
        XCTAssertTrue(BeaconRhythm.fastFlicker.isLit(atSecondsSinceStart: .nan))
        XCTAssertTrue(BeaconRhythm.fastFlicker.isLit(atSecondsSinceStart: .infinity))
        XCTAssertTrue(BeaconRhythm.fastFlicker.isLit(atSecondsSinceStart: 1e300))
        XCTAssertEqual(
            BeaconRhythm.doubleBlink.isLit(atSecondsSinceStart: 2.6),
            BeaconRhythm.doubleBlink.isLit(atMillisecondsSinceStart: 0)
        )
    }

    // MARK: - The screen is the light source

    func test_everyBeaconColour_isBrighterThanTheHuesWeRejected() {
        let pureRed = BeaconColor(red: 1, green: 0, blue: 0).relativeLuminance
        let pureBlue = BeaconColor(red: 0, green: 0, blue: 1).relativeLuminance
        for identity in BeaconIdentity.allCases {
            let luminance = identity.beaconColor.relativeLuminance
            XCTAssertGreaterThan(luminance, pureRed, identity.rawValue)
            XCTAssertGreaterThan(luminance, pureBlue, identity.rawValue)
        }
    }

    func test_dimmestColour_isCompensatedByTheHighestDutyCycle() {
        let dimmest = BeaconIdentity.allCases.min {
            $0.beaconColor.relativeLuminance < $1.beaconColor.relativeLuminance
        }
        XCTAssertEqual(dimmest, .magenta)
        XCTAssertEqual(BeaconIdentity.magenta.rhythm.dutyCycle, 1, accuracy: 0.0001)
    }

    func test_everyColour_isFullySaturated() {
        // A washed-out hue is the first thing club lighting destroys.
        for identity in BeaconIdentity.allCases {
            let c = identity.beaconColor
            XCTAssertEqual(max(c.red, max(c.green, c.blue)), 1, accuracy: 0.0001, identity.rawValue)
            XCTAssertLessThanOrEqual(min(c.red, min(c.green, c.blue)), 0.2, identity.rawValue)
        }
    }

    // MARK: - Helpers

    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        var result: [[T]] = []
        for (index, item) in items.enumerated() {
            var rest = items
            rest.remove(at: index)
            result.append(contentsOf: permutations(rest).map { [item] + $0 })
        }
        return result
    }
}
