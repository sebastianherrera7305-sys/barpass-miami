import XCTest
@testable import BarPass_app

@MainActor
final class HelpGuideStoreTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        HelpGuideStore.shared.resetGuide()
    }

    override func tearDown() async throws {
        HelpGuideStore.shared.resetGuide()
        try await super.tearDown()
    }

    private let tipV1 = HelpTip(id: "test.tip", route: .tonight, title: "T", description: "D", version: 1)
    private let tipV2 = HelpTip(id: "test.tip", route: .tonight, title: "T", description: "D updated", version: 2)

    func test_hasSeen_falseBeforeMarking() {
        XCTAssertFalse(HelpGuideStore.shared.hasSeen(tipV1))
    }

    func test_markAsSeen_thenHasSeen_true() {
        HelpGuideStore.shared.markAsSeen(tipV1)
        XCTAssertTrue(HelpGuideStore.shared.hasSeen(tipV1))
    }

    func test_markAsSeen_persistsToUserDefaults() {
        HelpGuideStore.shared.markAsSeen(tipV1)
        let raw = UserDefaults.standard.dictionary(forKey: "bp_help_seen_versions") as? [String: Int]
        XCTAssertEqual(raw?["test.tip"], 1)
    }

    func test_resetGuide_clearsSeenState() {
        HelpGuideStore.shared.markAsSeen(tipV1)
        HelpGuideStore.shared.resetGuide()
        XCTAssertFalse(HelpGuideStore.shared.hasSeen(tipV1))
    }

    /// The explicit ask: a tip whose registry version was bumped after an
    /// app update must resurface even though the user already saw the old
    /// version.
    func test_versionBump_resurfacesTip() {
        HelpGuideStore.shared.markAsSeen(tipV1)
        XCTAssertTrue(HelpGuideStore.shared.hasSeen(tipV1))
        XCTAssertFalse(HelpGuideStore.shared.hasSeen(tipV2),
            "A tip bumped to version 2 must count as unseen even though version 1 was marked seen")
    }

    func test_markingHigherVersionSeen_alsoSatisfiesLowerVersionCheck() {
        HelpGuideStore.shared.markAsSeen(tipV2)
        XCTAssertTrue(HelpGuideStore.shared.hasSeen(tipV1))
        XCTAssertTrue(HelpGuideStore.shared.hasSeen(tipV2))
    }

    func test_shouldShowIntro_trueBeforeFirstLaunch() {
        XCTAssertTrue(HelpGuideStore.shared.shouldShowIntro)
    }

    func test_markIntroShown_thenShouldShowIntro_false() {
        HelpGuideStore.shared.markIntroShown()
        XCTAssertFalse(HelpGuideStore.shared.shouldShowIntro)
    }

    func test_resetGuide_alsoResetsIntroFlag() {
        HelpGuideStore.shared.markIntroShown()
        HelpGuideStore.shared.resetGuide()
        XCTAssertTrue(HelpGuideStore.shared.shouldShowIntro)
    }

    func test_open_setsActiveAndCurrentRoute() {
        HelpGuideStore.shared.open(route: .explore)
        XCTAssertTrue(HelpGuideStore.shared.isActive)
        XCTAssertEqual(HelpGuideStore.shared.currentRoute, .explore)
    }

    func test_close_setsInactive() {
        HelpGuideStore.shared.open(route: .tonight)
        HelpGuideStore.shared.close()
        XCTAssertFalse(HelpGuideStore.shared.isActive)
    }
}
