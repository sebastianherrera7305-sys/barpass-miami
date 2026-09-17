import Foundation

/// Un ítem de la carta de un local, tal como lo publica el local.
///
/// Las filas de `venue_menu_items` no las escribe un usuario: salen de la
/// carta que el venue publica — a veces un HTML, a veces un JPG del que hubo
/// que leer los precios. Por eso cada fila carga su propia procedencia
/// (`source`, `sourceUrl`, `extractedAt`) y la pantalla la muestra: un precio
/// que no se puede auditar es un precio en el que no se puede confiar.
///
/// `price` es opcional a propósito. En la tabla es `numeric NULL`, y una carta
/// que dice "market price" o que simplemente no imprime el número es un HECHO
/// sobre ese trago. Mostrarlo como `$0` sería inventar un precio; la vista
/// dice "sin precio" y no se pierde el ítem.
struct VenueMenuItem: Identifiable, Codable, Equatable, Sendable {
    /// Cada columna nombrada. Nunca `select=*`: la tabla puede crecer y una
    /// carta se lee adentro de un local, donde cada byte se paga en segundos.
    static let columns = "id,venue_id,name,price,category,is_drink,source,source_url,extracted_at"

    let id: String
    let venueId: String
    let name: String
    /// NULL cuando la carta no publica el precio. Ver arriba.
    let price: Double?
    let category: String
    let isDrink: Bool
    let source: String
    let sourceUrl: String?
    let extractedAt: Date?
}

/// El orden en que una carta se lee de verdad: primero lo que la gente va a
/// tomar, después lo que va a comer, y al final el cajón de sastre.
///
/// Es un `String` crudo en la base (7 valores acordados), así que un valor
/// que no conozcamos no se descarta: cae en `.other` y el ítem se muestra
/// igual. Perder un trago por una categoría nueva sería peor que agruparlo mal.
enum VenueMenuCategory: String, CaseIterable, Sendable {
    case cocktail, beer, wine, shot, spirit, food, other

    init(raw: String) {
        self = VenueMenuCategory(rawValue: raw.lowercased()) ?? .other
    }

    /// Clave de traducción; el texto vive en los tres diccionarios.
    var titleKey: String { "menu.category.\(rawValue)" }

    var icon: String {
        switch self {
        case .cocktail: return "wineglass.fill"
        case .beer:     return "mug.fill"
        case .wine:     return "wineglass"
        case .shot:     return "flame.fill"
        case .spirit:   return "drop.fill"
        case .food:     return "fork.knife"
        case .other:    return "list.bullet"
        }
    }
}

/// De dónde salió una fila. Los cuatro valores que la tabla usa hoy; uno
/// desconocido se muestra crudo antes que ocultarse.
enum VenueMenuSource: Sendable {
    case websiteMenu, menuImage, userReport, manualResearch, unknown(String)

    init(raw: String) {
        switch raw {
        case "venue website menu": self = .websiteMenu
        case "venue menu image":   self = .menuImage
        case "user_report":        self = .userReport
        case "manual_research":    self = .manualResearch
        default:                   self = .unknown(raw)
        }
    }

    var titleKey: String? {
        switch self {
        case .websiteMenu:    return "menu.source.websiteMenu"
        case .menuImage:      return "menu.source.menuImage"
        case .userReport:     return "menu.source.userReport"
        case .manualResearch: return "menu.source.manualResearch"
        case .unknown:        return nil
        }
    }

    var rawLabel: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

protocol VenueMenuRepository: Sendable {
    /// La carta de un local. Vacía cuando el local no tiene carta cargada,
    /// que hoy es la mayoría del catálogo — no es un error.
    func items(for venueId: String) async throws -> [VenueMenuItem]
}

actor SupabaseVenueMenuRepository: VenueMenuRepository {

    func items(for venueId: String) async throws -> [VenueMenuItem] {
        let req = try SupabaseRESTClient.request(
            "GET", path: "venue_menu_items",
            queryItems: [
                URLQueryItem(name: "select", value: VenueMenuItem.columns),
                URLQueryItem(name: "venue_id", value: "eq.\(venueId)"),
                // Alfabético dentro de cada categoría; la vista agrupa.
                URLQueryItem(name: "order", value: "category.asc,name.asc"),
            ],
            // Pública de sólo lectura: no hay sesión que agregue nada.
            // Timeout corto por la misma razón que las historias — adentro
            // de un club la señal es mala y una carta que nunca resuelve es
            // peor que una entrada que no se dibuja.
            timeout: 12
        )
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([VenueMenuItem].self, from: data)
    }
}
