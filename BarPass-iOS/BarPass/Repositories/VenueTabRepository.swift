import Foundation

// MARK: - Modelos

/// Una cuenta abierta en un local. `joinCode` es lo que se le dicta a un
/// amigo para que se sume; `ownerId` sólo dice quién la abrió — en una cuenta
/// de grupo NO es el que paga todo (supabase/venue_tabs.sql).
struct VenueTab: Codable, Identifiable, Sendable {
    let id: String
    let venueId: String
    let ownerId: String
    let joinCode: String
    let status: String
    let openedAt: Date
    let closedAt: Date?

    var isOpen: Bool { status == "open" }
}

struct VenueTabMember: Codable, Identifiable, Sendable {
    let userId: String
    let joinedAt: Date
    let leftAt: Date?

    var id: String { userId }
}

/// Un consumo. `memberId` es quién lo tomó Y quién lo pagó: cada trago sale
/// de la billetera de su dueño, que es lo que hace que una cuenta de grupo se
/// pueda abrir sin fiarse de nadie.
struct VenueTabCharge: Codable, Identifiable, Sendable {
    let id: String
    let memberId: String
    let description: String
    let amount: Double
    let createdAt: Date
}

struct VenueTabDetail: Codable, Sendable {
    let tab: VenueTab
    let members: [VenueTabMember]
    let charges: [VenueTabCharge]

    /// Lo que va gastando el grupo entero, que es el número que la gente mira.
    var groupTotal: Double { charges.reduce(0) { $0 + $1.amount } }
    func total(for userId: String) -> Double {
        charges.filter { $0.memberId == userId }.reduce(0) { $0 + $1.amount }
    }
}

/// El código que se muestra en la barra. Vive tres minutos y sirve una sola
/// vez: la pantalla que lo muestra tiene que tratarlo como perecedero.
struct TabScanToken: Codable, Sendable {
    let token: String
    let expiresAt: Date
}

enum VenueTabError: LocalizedError {
    case notAuthenticated
    case tabNotFound
    case notAMember
    case tabClosed
    case rateLimited
    case backendDown
    case network

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return L10n.tSync("tab.error.signIn")
        case .tabNotFound:      return L10n.tSync("tab.error.notFound")
        case .notAMember:       return L10n.tSync("tab.error.notMember")
        case .tabClosed:        return L10n.tSync("tab.error.closed")
        case .rateLimited:      return L10n.tSync("tab.error.tooFast")
        case .backendDown:      return L10n.tSync("tab.error.backend")
        case .network:          return L10n.tSync("tab.error.network")
        }
    }

    /// El servidor manda códigos estables y nunca el mensaje crudo de
    /// Postgres (que traería nombres de tablas y constraints).
    static func from(code: String?, status: Int) -> VenueTabError {
        switch code {
        case "not_authenticated":       return .notAuthenticated
        case "tab_not_found", "not_found": return .tabNotFound
        case "not_a_member", "not_the_owner": return .notAMember
        case "tab_closed":              return .tabClosed
        case "rate_limited":            return .rateLimited
        case "backend_not_configured":  return .backendDown
        default:                        return status == 401 ? .notAuthenticated : .network
        }
    }
}

// MARK: - Repositorio

protocol VenueTabRepository: Sendable {
    /// Idempotente por (usuario, local): si ya hay una abierta, devuelve esa.
    func open(venueId: String) async throws -> (tabId: String, joinCode: String)
    func detail(tabId: String) async throws -> VenueTabDetail
    func join(code: String) async throws -> String
    /// `maxAmount` es el techo que la persona aprueba para ESTE código. No es
    /// una constante de la app: es la protección que justifica todo el diseño
    /// del token, y ponerle un valor fijo sería devolverla en silencio.
    func issueScanToken(tabId: String, maxAmount: Double) async throws -> TabScanToken
    func close(tabId: String) async throws
}

/// Habla con las rutas de Vercel (`/api/tab/...`), no con Supabase REST: el
/// cobro y la apertura viven ahí porque necesitan el service role y el
/// secreto del local.
final actor BarPassVenueTabRepository: VenueTabRepository {
    private let base = URL(string: "https://barpass-v2.vercel.app/api")!

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // Propia, no compartida: la de OrderHistoryService es `private` a ese
        // archivo. Postgres manda fracciones de segundo y PostgREST a veces no,
        // así que hay que aceptar las dos formas o un timestamp rompe la
        // pantalla entera.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "fecha inválida: \(raw)")
        }
        return d
    }()

    /// `appendingPathComponent` percent-escapa el `?`, así que "tab?tabId=x"
    /// se convertía en la ruta literal `/api/tab%3FtabId=x` y el servidor
    /// devolvía 404 sin que nada pareciera roto del lado del cliente.
    private func url(_ path: String, query: [String: String]) -> URL {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return comps.url!
    }

    private func request(_ method: String, _ path: String,
                         query: [String: String] = [:],
                         body: [String: Any]? = nil) async throws -> Data {
        guard let session = try? await SupabaseRESTClient.freshSession() else {
            throw VenueTabError.notAuthenticated
        }
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw VenueTabError.network }

        guard let http = response as? HTTPURLResponse else { throw VenueTabError.network }
        guard 200..<300 ~= http.statusCode else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])??["error"] as? String
            throw VenueTabError.from(code: code, status: http.statusCode)
        }
        return data
    }

    func open(venueId: String) async throws -> (tabId: String, joinCode: String) {
        let data = try await request("POST", "tab", body: ["venueId": venueId])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabId = json["tabId"] as? String, let code = json["joinCode"] as? String else {
            throw VenueTabError.network
        }
        return (tabId, code)
    }

    func detail(tabId: String) async throws -> VenueTabDetail {
        let data = try await request("GET", "tab", query: ["tabId": tabId])
        return try Self.decoder.decode(VenueTabDetail.self, from: data)
    }

    func join(code: String) async throws -> String {
        let data = try await request("POST", "tab/join", body: ["joinCode": code])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabId = json["tabId"] as? String else { throw VenueTabError.network }
        return tabId
    }

    func issueScanToken(tabId: String, maxAmount: Double) async throws -> TabScanToken {
        let data = try await request("POST", "tab/scan-token",
                                     body: ["tabId": tabId, "maxAmount": maxAmount])
        return try Self.decoder.decode(TabScanToken.self, from: data)
    }

    func close(tabId: String) async throws {
        _ = try await request("DELETE", "tab", query: ["tabId": tabId])
    }
}
