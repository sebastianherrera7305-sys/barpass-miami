import Foundation

/// Screens that can register Help targets. Deliberately NOT the same enum as
/// any navigation/tab type — Help's notion of "where am I" only needs to be
/// coarse enough to filter tooltips, not drive real navigation.
enum HelpRoute: String, CaseIterable {
    case tonight
    case explore
    case venueDetail
    case trips
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
    ]

    static func tips(for route: HelpRoute) -> [HelpTip] {
        tips.filter { $0.route == route }
    }

    static func tip(id: String) -> HelpTip? {
        tips.first { $0.id == id }
    }
}
