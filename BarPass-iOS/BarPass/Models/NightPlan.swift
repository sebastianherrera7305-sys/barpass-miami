import Foundation
import CoreLocation

// MARK: - AI night plan (Plan tab)

struct PlanStop: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let time: String
    let venueName: String
    let venueNeighborhood: String
    let venuePriceRange: String
    let note: String
    /// Real Supabase venue id, when a real AI plan resolved one — lets the
    /// UI deep-link to the actual venue page. Nil for `.sample()`'s
    /// local heuristic plans (never claimed a specific id) and for any AI
    /// stop the app couldn't match against its own loaded catalog.
    var venueId: String? = nil
}

struct NightPlan: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "Mi plan de noche"
    var stops: [PlanStop] = []
    var totalEst: String = ""
    var aiInsight: String = ""
    var createdAt: Date = .now
    /// True for a real Remy/LLM-generated plan (barpass-v2's /api/concierge)
    /// — `note`/`aiInsight` are free AI text here, not l10n keys, so the UI
    /// must render them as plain strings instead of running them through
    /// `l10n.t(...)`/`String(format:...)` the way `.sample()`'s keyed
    /// content needs. False for the local rule-based fallback.
    var isAIGenerated: Bool = false

    /// Real-time-aware plan: answers "where should I go right now" instead
    /// of assuming a fixed 8pm→10:30pm→12:30am evening progression. Every
    /// stop is picked and labeled from the venue's *actual* current status
    /// (live event / starting soon / open now / later tonight), never a
    /// hardcoded clock time, and closed venues with nothing happening are
    /// excluded entirely. Falls back to tomorrow's top picks — clearly
    /// labeled as such — only when literally nothing is active right now,
    /// so the feed is never empty.
    ///
    /// Runs on MainActor because it resolves l10n keys directly (badges
    /// need formatted values baked in, e.g. "Starts in 20 min") — the sole
    /// call site (`PlanView.generatePlan`) already invokes this inside
    /// `MainActor.run`.
    ///
    /// - Parameter userLocation: last known device coordinate, if location
    ///   permission was granted. When present, closer open venues/events
    ///   rank higher within their tier (never overriding the live/soon/open
    ///   priority order — just breaking ties among otherwise-equal picks).
    ///   When nil (permission denied, unavailable, or not yet requested),
    ///   distance is simply omitted from scoring — BarPass is single-market
    ///   (Miami) today, so there's no separate "default market" to fall back
    ///   to beyond the existing rating/trending signal.
    @MainActor
    static func sample(for prompt: String, venues: [BarPassVenue], userLocation: CLLocationCoordinate2D? = nil) -> NightPlan {
        let now = Date()
        let l10n = L10n.shared

        let promptKeys = Set(
            prompt.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        )
        // Deliberately excludes v.name — see ExperienceScorer.swift's
        // identical fix: matching keywords as raw substrings of a venue's
        // NAME text produces false positives ("Yard House" / "Miller's Ale
        // House" matching the "house" music-genre keyword).
        func haystack(_ v: BarPassVenue) -> String {
            ([v.type.rawValue, v.neighborhood] + v.vibes + v.tags + v.musicGenres.map(\.rawValue))
                .joined(separator: " ").lowercased()
        }
        func promptScore(_ v: BarPassVenue) -> Double {
            promptKeys.isEmpty ? 0 : Double(promptKeys.filter { haystack(v).contains($0) }.count)
        }
        // Distance bonus decays to 0 by ~20km (covers metro Miami) — a tie
        // breaker, not a hard filter, so it never buries a livelier stop
        // further away in favor of a dead one nearby.
        func distanceBonus(_ v: BarPassVenue) -> Double {
            guard let userLocation else { return 0 }
            let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            let venueLoc = CLLocation(latitude: v.latitude, longitude: v.longitude)
            let km = userLoc.distance(from: venueLoc) / 1000
            return max(0, 1 - km / 20) * 0.5
        }
        func popularity(_ v: BarPassVenue) -> Double {
            (v.isTrending ? 1 : 0) + v.rating * 0.2 + min(Double(v.reviewCount) / 10_000, 0.5)
                + promptScore(v) * 2 + distanceBonus(v)
        }

        struct Candidate { let venue: BarPassVenue; let tier: Int; let rankScore: Double; let time: String; let noteKey: String }
        var candidates: [Candidate] = []

        for v in venues {
            // Best (soonest-relevant, not-yet-finished) event at this venue, if any.
            let bestEvent = v.upcomingEvents
                .map { (event: $0, status: VenueTimeStatus.status(for: $0, now: now)) }
                .filter { $0.status.isVisible }
                .min { lhs, rhs in
                    let (lt, rt) = (eventTierRank(lhs.status), eventTierRank(rhs.status))
                    return lt != rt ? lt < rt : lhs.event.date < rhs.event.date
                }

            if let best = bestEvent {
                let tier: Int; let time: String; let noteKey: String
                switch best.status {
                case .liveNow:
                    tier = 0; time = l10n.t("plan.badge.live"); noteKey = "plan.note.liveEvent"
                case .endingSoon(let mins):
                    tier = 0; time = String(format: l10n.t("plan.badge.endingSoon"), max(mins, 1)); noteKey = "plan.note.liveEvent"
                case .upcoming(let mins) where mins <= 60:
                    tier = 1; time = String(format: l10n.t("plan.badge.startsInMin"), mins); noteKey = "plan.note.startingSoon"
                case .upcoming(let mins):
                    tier = 3; time = String(format: l10n.t("plan.badge.startsInMin"), mins); noteKey = "plan.note.startingSoon"
                case .finished:
                    continue // unreachable (filtered by isVisible above), but exhaustive
                }
                candidates.append(Candidate(venue: v, tier: tier, rankScore: popularity(v), time: time, noteKey: noteKey))
            } else if v.isOpenNow {
                let closeMins = VenueTimeStatus.minutesUntilClose(openTime: v.openTime, closeTime: v.closeTime, now: now)
                let closingSoon = (closeMins ?? .max) <= 45
                candidates.append(Candidate(
                    venue: v, tier: 2,
                    rankScore: popularity(v) + (v.hasHappyHour ? 0.5 : 0),
                    time: closingSoon ? l10n.t("plan.badge.closingSoon") : String(format: l10n.t("plan.badge.openUntil"), v.closeTime),
                    noteKey: "plan.note.openNow"
                ))
            }
            // Closed venue with nothing happening — excluded, not recommended.
        }

        var ranked = candidates.sorted { $0.tier != $1.tier ? $0.tier < $1.tier : $0.rankScore > $1.rankScore }
        var isFallback = false

        if ranked.isEmpty {
            // Nothing open or active anywhere — recommend tomorrow's top
            // picks instead of leaving the feed blank, clearly labeled.
            isFallback = true
            ranked = venues
                .sorted { popularity($0) > popularity($1) }
                .prefix(4)
                .map { Candidate(venue: $0, tier: 4, rankScore: popularity($0), time: l10n.t("plan.badge.tomorrow"), noteKey: "plan.note.tomorrow") }
        }

        let picks = Array(ranked.prefix(4))
        let stops = picks.map { c in
            PlanStop(
                time: c.time,
                venueName: c.venue.name,
                venueNeighborhood: c.venue.neighborhood,
                venuePriceRange: c.venue.priceTier.symbol ?? l10n.t("venue.crowd.na"),
                note: c.noteKey
            )
        }

        return NightPlan(
            title: prompt.isEmpty ? "Mi plan de noche" : prompt,
            stops: stops,
            totalEst: "$80–150 / persona",
            aiInsight: isFallback ? "plan.insight.emptyFallback" : "plan.insight.live"
        )
    }

    /// Priority order for picking the single most relevant event at a venue:
    /// live/ending-soon beats starting-imminently beats further-out upcoming.
    private static func eventTierRank(_ status: VenueTimeStatus.EventStatus) -> Int {
        switch status {
        case .liveNow, .endingSoon:       return 0
        case .upcoming(let mins):         return mins <= 60 ? 1 : 2
        case .finished:                   return 3
        }
    }

    /// Maps a real Remy/LLM response (APIClient.getConciergePlan) into the
    /// same NightPlan shape the UI already knows how to render. `venues` is
    /// the already-loaded catalog, used only to resolve a display
    /// neighborhood/price-tier per stop when the model's own `venueId`
    /// doesn't come through — the model was told to use real venues, but
    /// its JSON is untrusted output, not a database read.
    static func fromConcierge(_ response: APIClient.ConciergePlanResponse, prompt: String, venues: [BarPassVenue]) -> NightPlan {
        let byId = Dictionary(uniqueKeysWithValues: venues.map { ($0.id, $0) })
        let byName = Dictionary(venues.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        let stops = response.stops.map { stop -> PlanStop in
            let matched = stop.venueId.flatMap { byId[$0] } ?? byName[stop.venueName.lowercased()]
            return PlanStop(
                time: stop.time,
                venueName: stop.venueName,
                venueNeighborhood: matched?.neighborhood ?? "",
                venuePriceRange: matched?.priceTier.symbol ?? "",
                note: stop.note,
                venueId: matched?.id
            )
        }

        return NightPlan(
            title: response.title,
            stops: stops,
            totalEst: String(format: "$%.0f", response.totalEstimate),
            aiInsight: response.insiderTip,
            isAIGenerated: true
        )
    }

    /// Pulls a trailing ```json ... ``` fenced NightPlan out of one of
    /// Remy's chat replies, if the message ends in one — the chat prompt
    /// tells the model to end a message with this block only when it's
    /// actually delivering (or updating) a plan; a plain reply has none.
    /// Returns the visible chat text (fence stripped) alongside the parsed
    /// plan, or the original text with `plan: nil` if there's no fence or
    /// it didn't parse.
    static func extractFromChatReply(_ raw: String, venues: [BarPassVenue]) -> (text: String, plan: NightPlan?) {
        let (text, plan, _) = extractChatReplyParts(raw, venues: venues)
        return (text, plan)
    }

    /// Pulls EITHER a trailing ```json plan block OR a ```options quick-reply
    /// block out of one of Remy's chat replies — the prompt tells the model
    /// a message carries at most one of the two, never both. Options are
    /// tappable chips (2-4 short answers) for questions with a small,
    /// natural set of answers — "this is a tap-first mobile chat, not a
    /// typing test."
    ///
    /// Build 84 "writhing in code" (2026-10-08) was the model emitting a
    /// bare ``` fence with no `json`/`options` tag, or dropping the fence
    /// entirely — either shape silently fell through the loop below and
    /// the raw object rendered in the chat bubble. The streaming helper
    /// (`maskUnrenderableCodeBlock`) hides it mid-stream; here we re-tag
    /// the final text so the actual plan/options still parses even when
    /// the stream never saw the correct marker. reply-stream.ts documents
    /// the same incident and does the same rewrite server-side.
    static func extractChatReplyParts(_ raw: String, venues: [BarPassVenue]) -> (text: String, plan: NightPlan?, options: [String]) {
        let normalized = normalizeOpenFence(raw)
        for fenceTag in ["json", "options"] {
            guard let openRange = normalized.range(of: "```\(fenceTag)"),
                  let closeRange = normalized.range(of: "```", range: openRange.upperBound..<normalized.endIndex) else {
                continue
            }
            let body = String(normalized[openRange.upperBound..<closeRange.lowerBound])
            let visibleText = String(normalized[normalized.startIndex..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8) else { continue }

            if fenceTag == "json" {
                guard let response = try? JSONDecoder().decode(APIClient.ConciergePlanResponse.self, from: data) else { continue }
                return (visibleText, fromConcierge(response, prompt: "", venues: venues), [])
            } else {
                guard let options = try? JSONDecoder().decode([String].self, from: data), !options.isEmpty else { continue }
                return (visibleText, nil, Array(options.prefix(4)))
            }
        }
        // Nothing parsed. Mask any lingering code-looking block in the
        // visible text so the bubble never falls back to raw JSON — the
        // owner reports it as "pantalla virus" when it does. Belt and
        // suspenders: `normalizeOpenFence` already rewrote a bare fence to
        // tagged, but if JSONDecoder rejected the body (a malformed plan,
        // a prose code block), the untagged fence is still here.
        return (maskUnrenderableCodeBlock(normalized), nil, [])
    }

    /// If the model emitted a bare ``` fence with no `json`/`options` tag,
    /// rewrite that first ``` in place to the tagged form so the loop in
    /// `extractChatReplyParts` can still find it. Matches the classifier
    /// in `barpass-v2/src/features/ai/services/reply-stream.ts`: look at
    /// the first non-whitespace character after the fence — `{` → json,
    /// `[` → options. Anything else is left alone; a code block around
    /// prose is not something we touch.
    private static func normalizeOpenFence(_ raw: String) -> String {
        // Already tagged — nothing to rewrite.
        guard raw.range(of: "```json") == nil,
              raw.range(of: "```options") == nil,
              let bare = raw.range(of: "```") else {
            return raw
        }
        let after = raw[bare.upperBound...].drop(while: { $0.isWhitespace })
        guard let first = after.first else { return raw }
        let replacement: String
        switch first {
        case "{": replacement = "```json"
        case "[": replacement = "```options"
        default:  return raw
        }
        var copy = raw
        copy.replaceSubrange(bare, with: replacement)
        return copy
    }

    /// Mid-stream helper for `PlanView` / `RemyLiveView`: hides from the
    /// bubble any text that belongs to a code block whose closing fence
    /// hasn't arrived yet. Both views used to only match ```json/```options
    /// — a bare ``` fence (Build 84 "writhing in code", 2026-10-08) or an
    /// unfenced raw object (the model dropping the fence entirely) streamed
    /// into the bubble character by character. Both are now caught here.
    ///
    /// Prose never contains a brace per the concierge prompt, so a `{` or
    /// `[` at a line boundary (or at the start of the reply) is a block
    /// opening and gets hidden until the plan card / options chips take
    /// over. A lone brace at the very tail is held back the same way until
    /// the next character arrives — a stream-safe default.
    static func maskUnrenderableCodeBlock(_ text: String) -> String {
        // 1. Tagged fences the prompt documents.
        for tag in ["```json", "```options"] {
            if let range = text.range(of: tag) {
                return String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 2. Bare ``` fence followed by `{` or `[` — the Build 84 shape.
        if let range = text.range(of: "```") {
            let after = text[range.upperBound...].drop(while: { $0.isWhitespace })
            if let first = after.first, first == "{" || first == "[" {
                return String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 3. Unfenced object / array dropped straight into the reply.
        if let cut = unfencedCodeStart(text) {
            return String(text[text.startIndex..<cut])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Narrow match for an unfenced code block: a brace/bracket at the
    /// start of the reply or right after a newline, followed by either a
    /// quoted key/string or the stream's trailing edge. Returning early at
    /// the end-of-stream edge is deliberate — the next character hasn't
    /// arrived yet, so we hold the brace back instead of leaking it.
    private static func unfencedCodeStart(_ text: String) -> String.Index? {
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "{" || c == "[" {
                let afterBoundary: Bool
                if i == text.startIndex {
                    afterBoundary = true
                } else {
                    let prev = text[text.index(before: i)]
                    afterBoundary = prev.isNewline || prev == "\r"
                }
                if afterBoundary {
                    var j = text.index(after: i)
                    while j < text.endIndex, text[j].isWhitespace {
                        j = text.index(after: j)
                    }
                    if j == text.endIndex || text[j] == "\"" {
                        return i
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
