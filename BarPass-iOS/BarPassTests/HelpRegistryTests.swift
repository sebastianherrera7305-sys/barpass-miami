import XCTest
@testable import BarPass_app

final class HelpRegistryTests: XCTestCase {

    func test_tipsForRoute_tonight_returnsOnlyTonightTips() {
        let tips = HelpRegistry.tips(for: .tonight)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertTrue(tips.allSatisfy { $0.route == .tonight })
    }

    func test_tipsForRoute_explore_returnsOnlyExploreTips() {
        let tips = HelpRegistry.tips(for: .explore)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertTrue(tips.allSatisfy { $0.route == .explore })
    }

    func test_tipsForRoute_doesNotLeakOtherRoutes() {
        let tonightIDs = Set(HelpRegistry.tips(for: .tonight).map(\.id))
        let exploreIDs = Set(HelpRegistry.tips(for: .explore).map(\.id))
        XCTAssertTrue(tonightIDs.isDisjoint(with: exploreIDs),
            "A tip registered under one route must never appear when filtering for a different route")
    }

    func test_tip_byID_returnsExactMatch() {
        let tip = HelpRegistry.tip(id: "tonight.recommendedForYou")
        XCTAssertNotNil(tip)
        XCTAssertEqual(tip?.route, .tonight)
    }

    func test_tip_byID_unknownIDReturnsNil() {
        XCTAssertNil(HelpRegistry.tip(id: "does.not.exist"))
    }

    /// The anchor dictionary in `HelpOverlayView` is keyed by `id` — two
    /// tips sharing an id would silently overwrite one another's anchor.
    func test_allTips_haveUniqueIDs() {
        let ids = HelpRegistry.tips.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate HelpTip id found: \(ids)")
    }

    /// Copy convention from the design brief: short, never empty, never
    /// obviously a placeholder.
    ///
    /// `title`/`description` pasaron a ser `titleKey`/`descriptionKey` cuando
    /// la ayuda se localizó (HelpRegistry.swift). Así que ahora la pregunta
    /// útil no es si la clave está vacía — es si RESUELVE. Una clave que no
    /// está en la tabla vuelve como la clave misma, y "venueDetail.save.title"
    /// en pantalla es exactamente el bug que este test tiene que atrapar, en
    /// los tres idiomas.
    func test_allTips_resolveInEveryLanguage() {
        for tip in HelpRegistry.tips {
            for language in AppLanguage.allCases {
                for key in [tip.titleKey, tip.descriptionKey] {
                    let text = L10n.t(key, language: language)
                    XCTAssertFalse(
                        text.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(tip.id): \(key) está vacía en \(language.rawValue)"
                    )
                    XCTAssertNotEqual(
                        text, key,
                        "\(tip.id): \(key) no existe en \(language.rawValue) — se mostraría la clave cruda"
                    )
                }
            }
        }
    }

    func test_venueDetailRoute_hasSaveAndSkipLineTips() {
        let ids = Set(HelpRegistry.tips(for: .venueDetail).map(\.id))
        XCTAssertTrue(ids.contains("venueDetail.save"))
        XCTAssertTrue(ids.contains("venueDetail.skipLine"))
    }

    func test_tripsRoute_hasCreateTip() {
        let ids = Set(HelpRegistry.tips(for: .trips).map(\.id))
        XCTAssertTrue(ids.contains("trips.create"))
    }
}
