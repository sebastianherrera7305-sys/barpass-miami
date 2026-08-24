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
    let title: String
    let description: String   // 1–2 sentences, enforced by convention not code
    let version: Int

    init(id: String, route: HelpRoute, title: String, description: String, version: Int = 1) {
        self.id = id
        self.route = route
        self.title = title
        self.description = description
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
            title: "Recomendado para ti",
            description: "Combina lo que está pasando esta noche con lugares que podrían interesarte, según tus gustos reales."
        ),
        HelpTip(
            id: "explore.filters",
            route: .explore,
            title: "Filtros",
            description: "Descubre lugares por categoría — trending, happy hour, rooftops, música en vivo."
        ),
        HelpTip(
            id: "tonight.events",
            route: .tonight,
            title: "Esta noche",
            description: "Eventos reales que pasan hoy en venues de Miami — toca uno para ver el detalle."
        ),
        HelpTip(
            id: "venueDetail.save",
            route: .venueDetail,
            title: "Guardar lugar",
            description: "Guarda este venue como favorito para encontrarlo rápido después, en Tonight y en tu perfil."
        ),
        HelpTip(
            id: "venueDetail.skipLine",
            route: .venueDetail,
            title: "Skip the Line",
            description: "Compra tu acceso prioritario para este venue y entra sin esperar en la puerta."
        ),
        HelpTip(
            id: "trips.create",
            route: .trips,
            title: "Crear un trip",
            description: "Arma un recorrido de la noche con varios venues para vos y tu grupo."
        ),
    ]

    static func tips(for route: HelpRoute) -> [HelpTip] {
        tips.filter { $0.route == route }
    }

    static func tip(id: String) -> HelpTip? {
        tips.first { $0.id == id }
    }
}
