import Foundation
import os

// MARK: - Protocol

protocol ReviewSummaryService: Sendable {
    func summary(for venue: BarPassVenue) async -> String
}

// MARK: - Local implementation

/// Generates a Spanish-language venue summary from REAL venue data only
/// (tags, vibes, rating, arrival time, dress code, editorial) — no invented
/// facts. Swappable for an LLM-backed implementation behind the same
/// protocol. Results are cached for 5 minutes.
final class ConsoleReviewSummaryService: ReviewSummaryService {
    private static let log = OSLog(subsystem: "io.barpass", category: "ReviewSummary")

    /// NSCache requires reference types — small box for (text, timestamp).
    private final class Entry {
        let text: String
        let date: Date
        init(_ text: String) { self.text = text; date = Date() }
    }

    private static let ttl: TimeInterval = 300
    // NSCache is documented thread-safe.
    nonisolated(unsafe) private static let cache = NSCache<NSString, Entry>()

    func summary(for venue: BarPassVenue) async -> String {
        let key = venue.id as NSString
        if let hit = Self.cache.object(forKey: key), Date().timeIntervalSince(hit.date) < Self.ttl {
            return hit.text
        }

        // Simulated generation latency so the UI's loading state is honest.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let text = Self.compose(venue)
        Self.cache.setObject(Entry(text), forKey: key)
        os_log("[ReviewSummary] generated for %@", log: Self.log, type: .debug, venue.name)
        return text
    }

    private static func compose(_ v: BarPassVenue) -> String {
        var parts: [String] = []

        // Opening line: editorial (real Google data) or a data-derived one.
        if let editorial = v.editorial, !editorial.isEmpty {
            let first = editorial.components(separatedBy: "\n").first ?? editorial
            parts.append(first.hasSuffix(".") ? first : first + ".")
        } else {
            // musicGenres is never a real per-venue signal (confirmed via
            // Supabase audit: empty for 90% of venues, an identical
            // ["house","hip_hop"] literal stuck on one seed batch for the
            // rest, unrelated to venue type) — never mentioned here, per
            // this function's "real data only" contract.
            parts.append("\(v.type.rawValue) de \(v.neighborhood).")
        }

        if !v.vibes.isEmpty {
            parts.append("Ideal para: \(v.vibes.prefix(3).joined(separator: ", ").lowercased()).")
        }
        if !v.bestArrivalTime.isEmpty {
            parts.append("Mejor llegar \(v.bestArrivalTime.lowercased().hasPrefix("entre") ? "" : "alrededor de ")\(v.bestArrivalTime).")
        }
        if v.hasHappyHour, let until = v.happyHourUntil {
            parts.append("Happy hour hasta \(until).")
        }
        if v.reviewCount > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let count = formatter.string(from: NSNumber(value: v.reviewCount)) ?? "\(v.reviewCount)"
            parts.append(String(format: "Puntuación: %.1f/5 basado en %@ opiniones.", v.rating, count))
        }
        if !v.dressCode.isEmpty {
            parts.append("Código de vestimenta: \(v.dressCode.lowercased()).")
        }

        return parts.joined(separator: " ")
    }
}
