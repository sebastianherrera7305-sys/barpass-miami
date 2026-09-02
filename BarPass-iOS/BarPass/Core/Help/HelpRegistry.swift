import Foundation

/// Screens that can register Help targets. Deliberately NOT the same enum as
/// any navigation/tab type — Help's notion of "where am I" only needs to be
/// coarse enough to filter tooltips, not drive real navigation.
enum HelpRoute: String, CaseIterable {
    case tonight
    case explore
    case venueDetail
    case trips
    case plan
    case profile
}

/// One explainable element. `version` lets a later app update bump only the
/// tips that actually changed and have them resurface — see
/// `HelpGuideStore.hasSeen`.
struct HelpTip: Identifiable {
    let id: String            // matches the elementID passed to .helpTarget(id:)
    let route: HelpRoute
    /// Claves de l10n, NO el texto ya traducido. `HelpRegistry.tips` es un
    /// `static let` que se evalúa una sola vez, así que resolver acá
    /// congelaría el idioma del primer acceso y el cambio en caliente dejaría
    /// de funcionar en la ayuda. Se resuelven en HelpOverlayView.
    let titleKey: String
    let descriptionKey: String   // 1–2 oraciones, por convención no por código
    let version: Int

    init(id: String, route: HelpRoute, titleKey: String, descriptionKey: String, version: Int = 1) {
        self.id = id
        self.route = route
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.version = version
    }
}

/// Central config: route + elementID → tooltip metadata. Adding a new
/// explanation is adding one entry here — the overlay, persistence, and
/// anchor system never change. Screens register their elements with
/// `.helpTarget(id:)`; this is the other half of that contract.
enum HelpRegistry {
    static let tips: [HelpTip] = [
        HelpTip(
            id: "tonight.recommendedForYou",
            route: .tonight,
            titleKey: "help.tonight.recommendedForYou.title",
            descriptionKey: "help.tonight.recommendedForYou.desc"
        ),
        HelpTip(
            id: "explore.filters",
            route: .explore,
            titleKey: "help.explore.filters.title",
            descriptionKey: "help.explore.filters.desc"
        ),
        HelpTip(
            id: "tonight.events",
            route: .tonight,
            titleKey: "help.tonight.events.title",
            descriptionKey: "help.tonight.events.desc"
        ),
        HelpTip(
            id: "venueDetail.save",
            route: .venueDetail,
            titleKey: "help.venueDetail.save.title",
            descriptionKey: "help.venueDetail.save.desc"
        ),
        HelpTip(
            id: "venueDetail.skipLine",
            route: .venueDetail,
            titleKey: "help.venueDetail.skipLine.title",
            descriptionKey: "help.venueDetail.skipLine.desc"
        ),
        HelpTip(
            id: "trips.create",
            route: .trips,
            titleKey: "help.trips.create.title",
            descriptionKey: "help.trips.create.desc"
        ),
        // Profile tenía el botón de Ayuda apuntando a .profile sin un solo
        // tip registrado — la ruta existía en HelpRoute y MainTabView la
        // devolvía, pero HelpOverlayView filtra por ruta y no dibuja nada
        // si la lista sale vacía. El resultado: tocar "?" en Profile
        // oscurecía la pantalla y no había nada que tocar, indistinguible
        // de un botón roto. Estos dos son los primeros elementos reales.
        HelpTip(
            id: "profile.pointsCard",
            route: .profile,
            titleKey: "help.profile.pointsCard.title",
            descriptionKey: "help.profile.pointsCard.desc"
        ),
        HelpTip(
            id: "profile.wallet",
            route: .profile,
            titleKey: "help.profile.wallet.title",
            descriptionKey: "help.profile.wallet.desc"
        ),

        // Broader pass, 2026-09-02: "toca el botón de ayuda pero no ayuda ni
        // guía al usuario" — two tips per screen wasn't enough to actually
        // teach someone how to use the app. Every screen's real, non-obvious
        // controls get a tip now, not just the one or two that happened to
        // ship first.
        HelpTip(
            id: "tonight.vibeTags",
            route: .tonight,
            titleKey: "help.tonight.vibeTags.title",
            descriptionKey: "help.tonight.vibeTags.desc"
        ),
        HelpTip(
            id: "tonight.universities",
            route: .tonight,
            titleKey: "help.tonight.universities.title",
            descriptionKey: "help.tonight.universities.desc"
        ),
        HelpTip(
            id: "explore.toggleView",
            route: .explore,
            titleKey: "help.explore.toggleView.title",
            descriptionKey: "help.explore.toggleView.desc"
        ),
        HelpTip(
            id: "venueDetail.checkIn",
            route: .venueDetail,
            titleKey: "help.venueDetail.checkIn.title",
            descriptionKey: "help.venueDetail.checkIn.desc"
        ),
        HelpTip(
            id: "venueDetail.directions",
            route: .venueDetail,
            titleKey: "help.venueDetail.directions.title",
            descriptionKey: "help.venueDetail.directions.desc"
        ),
        HelpTip(
            id: "trips.joinByCode",
            route: .trips,
            titleKey: "help.trips.joinByCode.title",
            descriptionKey: "help.trips.joinByCode.desc"
        ),
        HelpTip(
            id: "plan.prompt",
            route: .plan,
            titleKey: "help.plan.prompt.title",
            descriptionKey: "help.plan.prompt.desc"
        ),
        HelpTip(
            id: "plan.quickIdeas",
            route: .plan,
            titleKey: "help.plan.quickIdeas.title",
            descriptionKey: "help.plan.quickIdeas.desc"
        ),

        // Full sweep, same date: the two passes above still left real
        // controls unexplained on every screen. This is every remaining
        // interactive element worth a first-timer's attention — nothing
        // decorative, nothing that already says exactly what it does in
        // its own label (flag/swatch pickers, sign in/out).
        HelpTip(
            id: "tonight.promptSearch",
            route: .tonight,
            titleKey: "help.tonight.promptSearch.title",
            descriptionKey: "help.tonight.promptSearch.desc"
        ),
        HelpTip(
            id: "tonight.hype",
            route: .tonight,
            titleKey: "help.tonight.hype.title",
            descriptionKey: "help.tonight.hype.desc"
        ),
        HelpTip(
            id: "tonight.stadiums",
            route: .tonight,
            titleKey: "help.tonight.stadiums.title",
            descriptionKey: "help.tonight.stadiums.desc"
        ),
        HelpTip(
            id: "explore.centerMap",
            route: .explore,
            titleKey: "help.explore.centerMap.title",
            descriptionKey: "help.explore.centerMap.desc"
        ),
        HelpTip(
            id: "venueDetail.review",
            route: .venueDetail,
            titleKey: "help.venueDetail.review.title",
            descriptionKey: "help.venueDetail.review.desc"
        ),
        HelpTip(
            id: "venueDetail.links",
            route: .venueDetail,
            titleKey: "help.venueDetail.links.title",
            descriptionKey: "help.venueDetail.links.desc"
        ),
        HelpTip(
            id: "trips.card",
            route: .trips,
            titleKey: "help.trips.card.title",
            descriptionKey: "help.trips.card.desc"
        ),
        HelpTip(
            id: "plan.saveShare",
            route: .plan,
            titleKey: "help.plan.saveShare.title",
            descriptionKey: "help.plan.saveShare.desc"
        ),
        HelpTip(
            id: "profile.passes",
            route: .profile,
            titleKey: "help.profile.passes.title",
            descriptionKey: "help.profile.passes.desc"
        ),
        HelpTip(
            id: "profile.homeAddress",
            route: .profile,
            titleKey: "help.profile.homeAddress.title",
            descriptionKey: "help.profile.homeAddress.desc"
        ),
        HelpTip(
            id: "profile.games",
            route: .profile,
            titleKey: "help.profile.games.title",
            descriptionKey: "help.profile.games.desc"
        ),
        HelpTip(
            id: "profile.autoplay",
            route: .profile,
            titleKey: "help.profile.autoplay.title",
            descriptionKey: "help.profile.autoplay.desc"
        ),
        HelpTip(
            id: "profile.city",
            route: .profile,
            titleKey: "help.profile.city.title",
            descriptionKey: "help.profile.city.desc"
        ),
        HelpTip(
            id: "profile.affiliation",
            route: .profile,
            titleKey: "help.profile.affiliation.title",
            descriptionKey: "help.profile.affiliation.desc"
        ),
    ]

    static func tips(for route: HelpRoute) -> [HelpTip] {
        tips.filter { $0.route == route }
    }

    static func tip(id: String) -> HelpTip? {
        tips.first { $0.id == id }
    }
}
