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
    case profile(id: String)    // future
    /// Opens the Plan tab — the Home Screen widget's "prompt" button
    /// target. No id: unlike the others, this route doesn't identify a
    /// resource, it identifies an intent, so it's parsed before the
    /// value-required cases below. Named `planPrompt` (not `tonightPrompt`)
    /// since 2026-09-01 — Plan absorbed this entry point when Tonight's own
    /// "Prompt Your Night" section was retired, see CLAUDE.md → "Plan
    /// Consolidation Roadmap".
    case planPrompt
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
    static func parse(_ url: URL) -> DeepLinkRoute? {
        let type: String
        let rawValue: String

        switch url.scheme?.lowercased() {
        case "barpass":
            // barpass://trip/abc123  →  host "trip", pathComponents ["/", "abc123"]
            guard let host = url.host, !host.isEmpty else { return nil }
            type = host.lowercased()
            // barpass://prompt — no id to carry, so no path segment required.
            if type == "prompt" { return .planPrompt }
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
