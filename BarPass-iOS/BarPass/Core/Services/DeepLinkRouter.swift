import Foundation

/// A parsed, navigable destination extracted from an incoming deep link.
///
/// Only `.trip` and `.venue` are wired to navigation today (S1); the rest are
/// parsed and carried so future steps can route them without touching the
/// parser again. Equatable so callers can diff/observe route changes.
enum DeepLinkRoute: Equatable {
    case trip(id: String)
    case venue(id: String)
    case pass(id: String)       // future
    case invite(code: String)   // future
    /// Enlace mágico de un grupo efímero: `barpass://group?id={groupId}`.
    /// Entra sin pedir el código de 6 caracteres.
    case group(id: String)
    case profile(id: String)    // future
    /// Opens Tonight with the Prompt Your Night text field already focused —
    /// the Home Screen widget's "prompt" button target. No id: unlike the
    /// others, this route doesn't identify a resource, it identifies an
    /// intent, so it's parsed before the value-required cases below.
    case tonightPrompt
    /// Home Screen quick actions (long-press the icon). Like `tonightPrompt`
    /// these name an intent, not a resource, so they carry no id.
    case explore
    case social
    case passes
    case feedback
    case me
}

/// Turns an incoming URL into a `DeepLinkRoute`. Pure and side-effect free so
/// it's fully unit-testable without the app running.
///
/// Supported shapes (type is the first segment, value the second):
///   - Custom scheme:  `barpass://trip/{id}`   (host = type, path = /{value})
///   - Web / universal: `https://barpass.app/trip/{id}` (path = /type/value)
///
/// Returns `nil` for anything unrecognized — unknown type, missing value, or
/// an unsupported scheme — so the caller can no-op instead of dead-ending or
/// crashing.
enum DeepLinkRouter {
    /// `barpass://group?id={uuid}`. Sólo el id, y sólo si es un UUID: cualquier
    /// otra cosa (sin id, id vacío, id que no es un UUID, otro parámetro) es un
    /// enlace que no se puede accionar y devuelve nil, nunca una ruta a medias.
    private static func groupRoute(from url: URL) -> DeepLinkRoute? {
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value,
              UUID(uuidString: id) != nil else { return nil }
        return .group(id: id)
    }

    static func parse(_ url: URL) -> DeepLinkRoute? {
        let type: String
        let rawValue: String

        switch url.scheme?.lowercased() {
        case "barpass":
            // barpass://trip/abc123  →  host "trip", pathComponents ["/", "abc123"]
            guard let host = url.host, !host.isEmpty else { return nil }
            type = host.lowercased()
            // barpass://prompt — no id to carry, so no path segment required.
            switch type {
            case "prompt": return .tonightPrompt
            case "map", "explore": return .explore
            case "social": return .social
            case "passes": return .passes
            case "feedback": return .feedback
            case "group": return groupRoute(from: url)
            case "me": return .me
            // "profile" SIN id es tu propio perfil; con id es el de otra
            // persona. El atajo tiene que mirar el path antes de contestar —
            // si no, barpass://profile/u1 abre tu perfil en vez del de u1,
            // y el que mandó el link nunca se entera de que no funcionó.
            case "profile" where url.pathComponents.allSatisfy({ $0 == "/" }): return .me
            default: break
            }
            rawValue = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        case "https", "http":
            // https://barpass.app/trip/abc123  →  ["/", "trip", "abc123"]
            let comps = url.pathComponents.filter { $0 != "/" }
            guard comps.count >= 2 else { return nil }
            type = comps[0].lowercased()
            rawValue = comps[1]
        default:
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        switch type {
        case "trip":    return .trip(id: value)
        case "venue":   return .venue(id: value)
        case "pass":    return .pass(id: value)
        case "invite":  return .invite(code: value)
        case "profile": return .profile(id: value)
        default:        return nil
        }
    }
}
