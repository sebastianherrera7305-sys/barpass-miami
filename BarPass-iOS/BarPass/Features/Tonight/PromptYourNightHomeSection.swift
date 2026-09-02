import SwiftUI

/// Compact "Prompt Your Night" control for the Home feed — the new front
/// door to the app, sitting where the passive "Where to tonight?" text used
/// to be. Deliberately NOT the full multi-stop route builder that lives in
/// Trips (`PromptYourNightView`); this is a single free-text + budget/vibe
/// query that ranks the SAME real venues Home already has via the SAME
/// `ExperienceScorer` Trips and `recommendedForYou` use — no parallel
/// filtering system, no fabricated data, no new venue card.
///
/// Isolated from `TonightView`'s own state on purpose: everything below
/// this section (Universities, Stadiums, Trending, Recommended, existing
/// venue cards, city state, tab bar) is untouched and still reachable
/// exactly as before, whether or not a search is active here.
struct PromptYourNightHomeSection: View {
    let venues: [BarPassVenue]
    /// Flips true when the Home Screen widget's "prompt" button opens the
    /// app via `barpass://prompt` (DeepLinkRouter → AppState → TonightView).
    /// Focusing here, not higher up, keeps the keyboard-focus concern local
    /// to the field that actually owns it.
    @Binding var focusRequested: Bool

    /// Deliberately NOT the `zoomNS` TonightView's own Trending/Recommended
    /// sections use. TestFlight feedback: a result card lost its name and
    /// photo — root cause was this section sharing that namespace, so a
    /// venue appearing here AND in Trending/Recommended at the same time
    /// (very common, both draw from the same catalog) registered the same
    /// `matchedTransitionSource` id twice concurrently, which is undefined
    /// behavior and broke one of the two card's rendering. A dedicated
    /// namespace can never collide with the rest of the screen.
    @Namespace private var zoomNS

    @ObservedObject private var l10n = L10n.shared
    @State private var prompt = ""
    @State private var selectedBudget: Budget? = nil
    @State private var selectedVibe: ExperienceIntent? = nil
    @State private var selectedGenre: MusicGenre? = nil
    @State private var results: [BarPassVenue]? = nil
    @FocusState private var promptFocused: Bool

    /// The genres real venues in this catalog actually carry (sourced from
    /// Google Places / manual research, same as everywhere else `musicGenres`
    /// is used) — not a curated subset, so a chip never promises a sound the
    /// data can't back up.
    private static let genres = MusicGenre.allCases

    /// Buckets over the venue catalog's real `priceTier` (1-4, sourced from
    /// Google Places price level via `enrich-venues.ts` — never invented).
    /// "$150+" intentionally applies no upper filter: a $150 budget doesn't
    /// mean refusing to show a $200 venue that's otherwise the best match.
    enum Budget: CaseIterable, Identifiable {
        case low, mid, high, open
        var id: Self { self }
        var label: String {
            switch self {
            case .low:  return "$25"
            case .mid:  return "$50"
            case .high: return "$100"
            case .open: return "$150+"
            }
        }
        var maxTier: PriceTier? {
            switch self {
            case .low:  return .tier1
            case .mid:  return .tier2
            case .high: return .tier3
            case .open: return nil
            }
        }
    }

    /// The five vibe chips from the spec, mapped onto existing
    /// `ExperienceIntent` cases so the scoring signals (keywords, preferred
    /// types, tag boosts) are the real ones already tuned elsewhere in the
    /// app instead of a second, parallel set of heuristics.
    private static let vibes: [ExperienceIntent] = [.nightlife, .liveMusic, .relax, .dateNight, .networking]

    private func vibeLabel(_ intent: ExperienceIntent) -> String {
        switch intent {
        case .nightlife:  return l10n.t("prompt.vibe.party")
        case .liveMusic:  return l10n.t("prompt.vibe.music")
        case .relax:      return l10n.t("prompt.vibe.chill")
        case .dateNight:  return l10n.t("prompt.vibe.date")
        case .networking: return l10n.t("prompt.vibe.upscale")
        default:          return l10n.t(intent.labelKey)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t("prompt.kicker"))
                    .font(.bpScaled(11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.bpAmber)
                Text(l10n.t("prompt.question"))
                    .font(.bpScaled(19, weight: .black))
                    .foregroundStyle(Color.bpInk)
            }

            TextField(l10n.t("prompt.placeholder"), text: $prompt)
                .focused($promptFocused)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                    .strokeBorder(promptFocused ? Color.bpAmber.opacity(0.5) : Color.bpInk.opacity(0.12)))
                .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))
                // TestFlight: "puse que quería ir a Space y no da respuesta" —
                // only the button called search(); the keyboard's Return key
                // (the instinctive way to submit a search field) did nothing.
                .submitLabel(.search)
                .onSubmit(search)

            Button(action: search) {
                HStack(spacing: 8) {
                    Text(l10n.t("prompt.cta"))
                    Image(systemName: "arrow.right")
                }
                .font(.bpScaled(15, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("prompt.cta"), hint: l10n.t("night.build.hint"), isButton: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Budget.allCases) { b in budgetChip(b) }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.vibes) { v in vibeChip(v) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("prompt.genreLabel"))
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.genres, id: \.self) { g in genreChip(g) }
                    }
                }
            }

            if let results {
                resultsView(results)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.08)))
        .helpTarget("tonight.promptSearch")
        .onChange(of: focusRequested) { _, requested in
            guard requested else { return }
            promptFocused = true
            focusRequested = false
        }
    }

    private func budgetChip(_ b: Budget) -> some View {
        let on = selectedBudget == b
        return Button {
            BPHaptics.light()
            selectedBudget = on ? nil : b
        } label: {
            Text(b.label)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: b.label, isButton: true)
    }

    private func vibeChip(_ v: ExperienceIntent) -> some View {
        let on = selectedVibe == v
        let label = vibeLabel(v)
        return Button {
            BPHaptics.light()
            selectedVibe = on ? nil : v
        } label: {
            HStack(spacing: 5) {
                Text(v.emoji)
                Text(label).font(.bpScaled(13, weight: .semibold))
            }
            .foregroundStyle(on ? .black : Color.bpInk)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, isButton: true)
    }

    private func genreChip(_ g: MusicGenre) -> some View {
        let on = selectedGenre == g
        return Button {
            BPHaptics.light()
            selectedGenre = on ? nil : g
        } label: {
            Text(g.rawValue)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: g.rawValue, isButton: true)
    }

    private func resultsView(_ results: [BarPassVenue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("prompt.results"))
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
                Spacer()
                Button {
                    BPHaptics.light()
                    self.results = nil
                } label: {
                    Text(l10n.t("plan.askAgain"))
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpAmber)
                }
                .buttonStyle(.plain)
            }

            if results.isEmpty {
                Text(l10n.t("night.noMatch"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: BPSpacing.md) {
                        ForEach(results) { venue in
                            NavigationLink(destination: VenueDetailView(venue: venue).bpZoomDestination(id: venue.id, in: zoomNS)) {
                                HeroVenueCard(venue: venue)
                                    .bpZoomSource(id: venue.id, in: zoomNS)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func search() {
        promptFocused = false
        BPHaptics.medium()

        var intents: Set<String> = []
        if let selectedVibe { intents.insert(selectedVibe.rawValue) }
        let context = TripContext(intents: intents, prompt: prompt)
        let now = Date()
        let coordinate = UserLocationProvider.shared.coordinate

        // TestFlight: "por qué recomiendas lugares que tú no irías" — a
        // real, low-profile venue that happens to contain a searched
        // keyword (e.g. a small café whose Google category loosely matches)
        // could outrank an actually-famous spot, because ExperienceScorer's
        // keyword-match bonus (+1.0 per hit) dwarfs its own popularity term
        // (`reviewCount`, capped at +0.5 — a shared formula other screens
        // also rely on, so not touched globally). "Known" has no honest
        // signal in the data except real review volume, so Prompt Your
        // Night — the one screen explicitly promising "places you'd
        // actually go" — weighs it far more here: same real reviewCount
        // field everywhere else, just a bigger say in this ranking.
        var ranked = venues
            .map { venue -> (BarPassVenue, Double) in
                let base = ExperienceScorer.score(
                    venue: venue,
                    passport: MusicProfileStore.shared.passport,
                    context: context,
                    now: now,
                    userCoordinate: coordinate
                )
                let fameBoost = min(Double(venue.reviewCount) / 500.0, 6.0)
                return (venue, base + fameBoost)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        // "Los que son restaurante son restaurantes, los que son bar son
        // bares y los que son discoteca son discoteca" — a vibe's
        // `preferredTypes` (real, already-tuned per intent: Party→Club
        // only, Date→Rooftop/Lounge/Restaurant, etc.) was only ever a soft
        // scoring nudge, so a restaurant with a lucky keyword/popularity
        // score could still win a "Party" search. Picking a vibe now hard-
        // filters to venues of that vibe's real preferred types — no vibe
        // selected still means no type restriction (a bare free-text
        // search shouldn't get one invented).
        // Resolved before the vibe filter runs, because an explicitly named
        // genre has to survive it — see the exemption below.
        let effectiveGenre = selectedGenre ?? Self.detectGenre(in: prompt)

        if let selectedVibe {
            let allowedTypes = selectedVibe.profile.preferredTypes
            if !allowedTypes.isEmpty {
                // TestFlight: asking for House with the "Music" chip returned
                // Brickell cocktail bars. That chip is `.liveMusic`, whose
                // preferredTypes are [.lounge, .bar] — it means live bands
                // (jazz, salsa), so it filtered out every one of the 54 clubs
                // carrying house, 38% of the house venues in the catalogue and
                // the only type the genre actually lives in. A named genre is a
                // far more specific request than a broad vibe chip, so a venue
                // that really carries the asked-for genre is never dropped for
                // being the "wrong" type; the vibe still shapes the ranking
                // through ExperienceScorer above.
                ranked = ranked.filter { venue in
                    if let effectiveGenre, venue.musicGenres.contains(effectiveGenre) { return true }
                    return allowedTypes.contains(venue.type)
                }
            }
        }

        // TestFlight feedback: asking for something cheap surfaced an
        // Airport Lounge — `.unknown` (no Google Places price data) was
        // bypassing the filter unconditionally, so an unpriced upscale
        // venue could slip through even the $25 bucket. `.open` ($150+)
        // already has no real ceiling (`maxTier` is nil, this block never
        // runs), so the bypass was only ever wrong for the three buckets
        // that DO mean something — dropped instead of guessed at.
        if let maxTier = selectedBudget?.maxTier {
            ranked = ranked.filter { $0.priceTier != .unknown && $0.priceTier.rawValue <= maxTier.rawValue }
        }

        // Genre is a real signal on the venue (`musicGenres`, sourced the
        // same way as everywhere else it's used) — a soft preference, not a
        // hard filter: venues that actually carry the picked genre float to
        // the top (their ExperienceScorer order preserved among themselves),
        // but a great match with no genre tag still shows rather than
        // vanishing, same reasoning as the budget bucket above.
        // TestFlight: "pedía por una noche de House electrónica... y la
        // aplicación no se la dio" — they typed the genre into the free-text
        // field instead of tapping a genre chip. ExperienceScorer's haystack
        // match treats "house" in the prompt as one keyword among many
        // (rating, trending, tag boosts...), so a highly-rated venue that
        // doesn't play house at all could easily outrank a real house venue.
        // The chip's hard float-to-top only ran for `selectedGenre`; a genre
        // named in plain text deserves the exact same treatment.
        if let effectiveGenre {
            let matching = ranked.filter { $0.musicGenres.contains(effectiveGenre) }
            let rest = ranked.filter { !$0.musicGenres.contains(effectiveGenre) }
            ranked = matching + rest
        }

        // TestFlight: cards showing the photo but missing name/rating —
        // each HeroVenueCard already runs its own `.bpEntrance` animation
        // on appear. Wrapping this state change in ANOTHER animation meant
        // every new search result was animating on two competing clocks at
        // once (the outer spring driving layout, the card's own internal
        // entrance driving its offset/opacity) — SwiftUI could catch a
        // partially-settled frame from that conflict, and a screenshot or
        // fast glance landed on it. bpEntrance alone is enough motion.
        results = Array(ranked.prefix(10))
    }

    /// Matches a `MusicGenre` by its own raw value (already how the chips
    /// read) plus the handful of Spanish/alternate spellings someone would
    /// actually type — not a translation layer, just the real words for the
    /// same real genres already in the venue data.
    private static func detectGenre(in prompt: String) -> MusicGenre? {
        let text = prompt.lowercased()
        let synonyms: [MusicGenre: [String]] = [
            .edm: ["edm", "electronica", "electrónica", "electronic"],
            .house: ["house", "techno"],
            .latin: ["latin", "latino", "latina"],
            .hipHop: ["hip hop", "hip-hop", "hiphop", "rap"],
            .reggaeton: ["reggaeton", "reggaetón"],
            .pop: ["pop"],
            .live: ["live music", "música en vivo", "musica en vivo", "banda en vivo"],
            .jazz: ["jazz"],
            .techHouse: ["tech house"],
            .rnb: ["r&b", "rnb", "r & b"],
        ]
        for genre in MusicGenre.allCases {
            let words = [genre.rawValue.lowercased()] + (synonyms[genre] ?? [])
            if words.contains(where: { text.contains($0) }) { return genre }
        }
        return nil
    }
}
