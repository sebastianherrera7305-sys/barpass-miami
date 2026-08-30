import SwiftUI

struct TonightView: View {
    @Namespace private var zoomNS
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var selectedTag: String? = nil
    /// Rollback switch for the "Prompt Your Night" home section — flip to
    /// false to instantly restore the old passive "Where to tonight?" Home
    /// without reverting any code.
    private let usePromptYourNightHome = true

    /// Mood Mode — browse by experience, not venue type. Each mood maps to
    /// keywords matched against type/vibes/tags/music (same approach as
    /// NightPlanner) so selection actually filters the feed.
    private struct Mood: Hashable {
        let label: String
        let keywords: [String]
    }

    private var moods: [Mood] {
        [
            .init(label: "🔥 " + l10n.t("mood.trending"),   keywords: ["trending"]),
            .init(label: "🎉 " + l10n.t("mood.party"),      keywords: ["club", "edm", "house", "techno", "packed", "reggaeton"]),
            .init(label: "🍸 " + l10n.t("mood.cocktails"),  keywords: ["cocktail", "lounge", "bar", "mixology"]),
            .init(label: "🥂 " + l10n.t("mood.dateNight"),  keywords: ["date", "romantic", "rooftop", "lounge", "upscale", "views", "restaurant"]),
            .init(label: "🍽️ " + l10n.t("mood.dinner"),     keywords: ["restaurant", "dinner", "food"]),
            .init(label: "🎵 " + l10n.t("mood.liveMusic"),  keywords: ["live", "jazz", "salsa", "latin", "band"]),
            .init(label: "🌇 " + l10n.t("mood.rooftop"),    keywords: ["rooftop", "sunset", "views", "terrace"]),
            .init(label: "🏈 " + l10n.t("mood.sports"),     keywords: ["sports", "sport", "game", "screens"]),
            // "age:" keywords are a marker read by matches() below, not text
            // searched against venue fields — these check the real, research-
            // verified venue.ageBrackets instead of a keyword heuristic, same
            // distinction as the Trending case.
            .init(label: "🎓 18-25", keywords: ["age:18_25"]),
            .init(label: "💼 25-35", keywords: ["age:25_35"]),
            .init(label: "🥂 35-50", keywords: ["age:35_50"]),
        ]
    }

    private func matches(_ venue: BarPassVenue, _ mood: Mood) -> Bool {
        // Matched by keyword identity, not the (now-localized) label text —
        // "trending" is the marker, same pattern as the "age:" markers below.
        if mood.keywords == ["trending"] { return venue.isTrending }
        if let marker = mood.keywords.first, marker.hasPrefix("age:") {
            return venue.ageBrackets.contains(String(marker.dropFirst(4)))
        }
        let haystack = ([venue.type.rawValue, venue.name] + venue.vibes + venue.tags
            + venue.musicGenres.map { $0.rawValue }).joined(separator: " ").lowercased()
        return mood.keywords.contains { haystack.contains($0) }
    }

    private var favoriteVenues: [BarPassVenue] {
        venueStore.venues.filter { favorites.ids.contains($0.id) }
    }

    /// Venues que matchean con la música conectada del usuario — el resultado
    /// accionable del Hype card, no solo un número decorativo.
    private var musicMatchedVenues: [BarPassVenue] {
        guard let passport = MusicProfileStore.shared.passport else { return [] }
        return HypeEngine.matchedVenues(passport: passport, venues: venueStore.venues, limit: 12)
    }

    /// Home Feed's Experience Scorer section (Venue Intelligence Roadmap,
    /// Home Feed Step 1) — ranks by rating/trending/open-now/event/
    /// experience-tag/music-taste signals via the same ExperienceScorer
    /// Trips uses, called with an empty TripContext since Home has no
    /// "what are you feeling" prompt UI (unlike PromptYourNightView).
    /// Unlike musicMatchedVenues below, this never returns empty just
    /// because Apple Music isn't connected — passport is one signal among
    /// several here, not a hard requirement.
    /// Real per-type preference from the user's own favorites (FavoritesStore)
    /// — a type only counts once there are ≥2 favorites of it, so a single
    /// one-off favorite doesn't skew the whole feed. Empty for a user with
    /// no favorites, never a guessed preference.
    private var favoriteTypeSignal: Set<VenueType> {
        let counts = Dictionary(grouping: favoriteVenues, by: \.type).mapValues(\.count)
        return Set(counts.filter { $0.value >= 2 }.keys)
    }

    private var recommendedForYou: [BarPassVenue] {
        let context = TripContext()
        let now = Date()
        let coordinate = UserLocationProvider.shared.coordinate
        let favTypes = favoriteTypeSignal
        let ranked = venueStore.venues
            .map { venue in
                (venue, ExperienceScorer.score(
                    venue: venue,
                    passport: MusicProfileStore.shared.passport,
                    context: context,
                    now: now,
                    userCoordinate: coordinate,
                    favoriteTypes: favTypes
                ))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        // Best-first, not a strict round-robin: a genuinely excellent venue
        // can still rank above a mediocre one of a different type. The cap
        // only kicks in once a single type would otherwise fill the whole
        // section (e.g. every club scoring high on a Friday night) — real
        // variety without discarding the top scorer for looking "too club-y".
        let maxPerType = 5
        var picked: [BarPassVenue] = []
        var countByType: [VenueType: Int] = [:]
        for v in ranked {
            guard countByType[v.type, default: 0] < maxPerType else { continue }
            picked.append(v)
            countByType[v.type, default: 0] += 1
            if picked.count == 12 { break }
        }
        if picked.count < 12 {
            let pickedIds = Set(picked.map(\.id))
            for v in ranked where !pickedIds.contains(v.id) {
                picked.append(v)
                if picked.count == 12 { break }
            }
        }
        return picked
    }

    private var moodVenues: [BarPassVenue] {
        guard let tag = selectedTag, let mood = moods.first(where: { $0.label == tag }) else { return [] }
        return venueStore.venues.filter { matches($0, mood) }
            .sorted { ($0.isTrending ? 1 : 0, $0.rating) > ($1.isTrending ? 1 : 0, $1.rating) }
    }

    /// Evita que la misma venue aparezca repetida en varias secciones del
    /// mismo scroll — antes trending/happy hour/abiertos ahora/barrio no
    /// tenían ninguna exclusión entre sí ni con favoritos/music match, así
    /// que una venue popular podía salir 4 veces seguidas.
    private struct DedupedFeed {
        let trending: [BarPassVenue]
        let happyHour: [BarPassVenue]
        let openNow: [BarPassVenue]
        /// Top 3 neighborhoods by venue count in the current city — real
        /// data-derived grouping, not 3 Miami names hardcoded everywhere.
        /// Each neighborhood's venues are sorted by review_count (the
        /// closest real proxy for "most famous / most people want to go")
        /// with rating as a tiebreaker, so the front of each section is
        /// the neighborhood's actual most-popular spot, not DB insertion
        /// order.
        let neighborhoods: [(name: String, venues: [BarPassVenue])]
    }

    private var dedupedFeed: DedupedFeed {
        var shown = Set(favoriteVenues.map(\.id))
        shown.formUnion(musicMatchedVenues.map(\.id))
        shown.formUnion(recommendedForYou.map(\.id))

        func take(_ venues: [BarPassVenue]) -> [BarPassVenue] {
            let fresh = venues.filter { !shown.contains($0.id) }
            shown.formUnion(fresh.map(\.id))
            return fresh
        }

        let byNeighborhood = Dictionary(grouping: venueStore.venues, by: \.neighborhood)
        let topNeighborhoods = byNeighborhood
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map { name, venues -> (name: String, venues: [BarPassVenue]) in
                let ranked = venues.sorted {
                    $0.reviewCount != $1.reviewCount ? $0.reviewCount > $1.reviewCount : $0.rating > $1.rating
                }
                return (name, take(ranked))
            }

        return DedupedFeed(
            trending:      take(venueStore.trending),
            happyHour:     take(venueStore.happyHour),
            openNow:       take(venueStore.openNow),
            neighborhoods: topNeighborhoods
        )
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: BPSpacing.xl) {
                    header
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.top, 60)

                    // "Prompt Your Night" — the new front door, replacing the
                    // passive "Where to tonight?" line's role (that Text is
                    // dropped from `header` below since this takes over
                    // immediately underneath it). Isolated component, real
                    // venue data, same ExperienceScorer everything else on
                    // this screen already uses — nothing below this line
                    // moved, changed, or lost its own state.
                    if usePromptYourNightHome {
                        PromptYourNightHomeSection(venues: venueStore.venues, focusRequested: $appState.focusPromptRequested)
                            .padding(.horizontal, BPSpacing.lg)
                    }

                    HypeWeekCard()
                        .padding(.horizontal, BPSpacing.lg)

                    if let city = venueStore.selectedCity {
                        NavigationLink(destination: UniversityListView(city: city)) {
                            universitiesEntryCard
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, BPSpacing.lg)
                    }

                    NavigationLink(destination: StadiumsListView()) {
                        stadiumsEntryCard
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, BPSpacing.lg)

                    vibeTags

                    if venueStore.isLoading {
                        skeletonContent
                    } else if let tag = selectedTag {
                        // Mood Mode: the selected experience takes over the feed.
                        if moodVenues.isEmpty {
                            VStack(spacing: 8) {
                                Text("😴").font(.bpScaled(40))
                                Text(l10n.t("home.mood.empty"))
                                    .font(.bpScaled(14)).foregroundStyle(Color.bpTextSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else {
                            section(title: String(format: l10n.t("home.mood.count"), tag, moodVenues.count),
                                    venues: Array(moodVenues.prefix(3)), style: .hero)
                            if moodVenues.count > 3 {
                                section(title: l10n.t("home.mood.more"),
                                        venues: Array(moodVenues.dropFirst(3).prefix(12)), style: .card)
                            }
                        }
                    } else {
                        if !favoriteVenues.isEmpty {
                            section(title: l10n.t("home.favorites"), venues: favoriteVenues, style: .card)
                        }

                        if !musicMatchedVenues.isEmpty {
                            section(title: l10n.t("home.forYou"), venues: musicMatchedVenues, style: .hero)
                        }

                        if !recommendedForYou.isEmpty {
                            section(title: l10n.t("home.recommended"), venues: recommendedForYou, style: .hero)
                                .helpTarget("tonight.recommendedForYou")
                        }

                        if !tonightEvents.isEmpty {
                            eventsTonightSection
                        }

                        let feed = dedupedFeed

                        if !feed.trending.isEmpty {
                            section(title: l10n.t("home.trending"), venues: feed.trending, style: .hero)
                        }

                        if !feed.happyHour.isEmpty {
                            section(title: l10n.t("home.happyHour"), venues: feed.happyHour, style: .card)
                        }

                        if !feed.openNow.isEmpty {
                            section(title: l10n.t("home.openNow"), venues: feed.openNow, style: .card)
                        }

                        ForEach(feed.neighborhoods, id: \.name) { entry in
                            if !entry.venues.isEmpty {
                                section(title: "📍 \(entry.name)", venues: entry.venues, style: .card)
                            }
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
            .refreshable { await venueStore.forceRefresh() }
        }
        // One-shot, cached in UserLocationProvider — never a per-card fetch.
        // If permission is denied, `coordinate` just stays nil and every
        // distance-based signal in the scorer is silently absent.
        //
        // Delayed ~2.5s so the system permission dialog doesn't fire the
        // instant Tonight appears — it was racing the first-launch Help
        // intro banner (shown after 800ms) and covering the whole screen
        // before a user could even see it, let alone try Help. Not a
        // functional change: the location request still fires every
        // session, just not in the first eyeblink.
        .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            UserLocationProvider.shared.refreshOnce()
        }
    }

    private var skeletonContent: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            ShimmerSkeleton(width: 200, height: 18)
                .padding(.horizontal, BPSpacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BPSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BPRadius.xl)
                            .fill(Color.bpInk.opacity(0.04))
                            .frame(width: 280, height: 180)
                            .shimmer()
                            .overlay(
                                VStack(alignment: .leading, spacing: 8) {
                                    ShimmerSkeleton(width: 60, height: 10)
                                    ShimmerSkeleton(width: 150, height: 18)
                                    ShimmerSkeleton(width: 100, height: 10)
                                }
                                .padding(16),
                                alignment: .bottomLeading
                            )
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
        .bpLoadingRegion(l10n.t("a11y.loading"))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Was hardcoded "MIAMI" regardless of which city's venues were
            // actually showing — the app now serves 23 cities (per Supabase),
            // so a New York or Chicago session showed a wrong, misleading
            // label. Real bug surfaced alongside the city-filter fallback
            // fix in VenueStore: a New York feed under a "MIAMI" header
            // looked like venues from the wrong city had leaked in, when
            // the feed itself was actually correctly filtered.
            BarPassLogo(subtitle: venueStore.selectedCity?.uppercased() ?? l10n.t("home.allCities"))
                .padding(.bottom, 4)

            Text(greeting)
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)

            // Dropped in favor of PromptYourNightHomeSection directly below,
            // which now owns "what do you want tonight?" — kept behind the
            // same flag so disabling the section restores this line too.
            if !usePromptYourNightHome {
                Text(l10n.t("home.where"))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .bpAccessibility(label: greeting, hint: l10n.t("tonight.greeting.hint"))
    }

    // MARK: - Universities entry

    private var universitiesEntryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.bpScaled(20))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("greek.universityList.title"))
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("greek.universityList.hint"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpTextTertiary)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: l10n.t("greek.universityList.title"), hint: l10n.t("greek.universityList.hint"), isButton: true)
    }

    private var stadiumsEntryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sportscourt.fill")
                .font(.bpScaled(20))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("stadiums.entry.title"))
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("stadiums.entry.hint"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpTextTertiary)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: l10n.t("stadiums.entry.title"), hint: l10n.t("stadiums.entry.hint"), isButton: true)
    }

    // MARK: - Vibe tags

    private var vibeTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(moods.map(\.label), id: \.self) { tag in
                    Button {
                        BPHaptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    } label: {
                        Text(tag)
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(selectedTag == tag ? .black : Color.bpInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTag == tag
                                    ? Color.bpAmber
                                    : Color.bpInk.opacity(0.08))
                            )
                            .overlay(
                                Capsule().strokeBorder(selectedTag == tag
                                    ? Color.clear
                                    : Color.bpInk.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: tag, hint: l10n.t("tonight.tag.hint"), isButton: true)
                }
            }
            .padding(.horizontal, BPSpacing.lg)
        }
    }

    // MARK: - Events tonight (flyer rail)

    /// Live-now/ending-soon events plus upcoming ones within the next 7
    /// days, paired with their venue. Events that have actually finished
    /// (per `VenueTimeStatus`) are never shown — previously this used a
    /// flat "-6h to +36h around start" window, which kept an event visible
    /// for 6 hours after it started even once it was long over. The 36h
    /// upcoming horizon was widened to 7 days because real event data is
    /// sparse (only a handful of venues have any events loaded, spaced
    /// days apart) — a 36h window sat empty on most days even when real
    /// upcoming events existed just outside it.
    private var tonightEvents: [(event: VenueEvent, venue: BarPassVenue)] {
        let now = Date()
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return venueStore.venues
            .flatMap { v in v.upcomingEvents.map { (event: $0, venue: v) } }
            .filter { pair in
                switch VenueTimeStatus.status(for: pair.event, now: now) {
                case .liveNow, .endingSoon:       return true
                case .upcoming(let startsInMins): return Double(startsInMins * 60) < horizon.timeIntervalSince(now)
                case .finished:                   return false
                }
            }
            .sorted { $0.event.date < $1.event.date }
    }

    private var eventsTonightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("home.eventsTonight"))
                .font(.bpScaled(20, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, BPSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(tonightEvents, id: \.event.id) { pair in
                        NavigationLink(destination: VenueDetailView(venue: pair.venue).bpZoomDestination(id: pair.venue.id, in: zoomNS)) {
                            EventFlyerCard(event: pair.event, venue: pair.venue)
                                .bpZoomSource(id: pair.venue.id, in: zoomNS)
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: String(format: l10n.t("tonight.eventAt"), pair.event.title, pair.venue.name), hint: l10n.t("tonight.event.hint"), isButton: true)
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
        .helpTarget("tonight.events")
    }

    // MARK: - Sections

    private func section(title: String, venues: [BarPassVenue], style: CardStyle) -> some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            Text(title)
                .font(.bpHeadline())
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, BPSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BPSpacing.md) {
                    ForEach(venues) { venue in
                        NavigationLink(destination: VenueDetailView(venue: venue).bpZoomDestination(id: venue.id, in: zoomNS)) {
                            Group {
                                switch style {
                                case .hero: HeroVenueCard(venue: venue)
                                case .card: SmallVenueCard(venue: venue)
                                }
                            }
                            .bpZoomSource(id: venue.id, in: zoomNS)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return l10n.t("greet.morning")
        case 12..<18: return l10n.t("greet.afternoon")
        default: return l10n.t("greet.night")
        }
    }
}

// MARK: - Hero Card

struct HeroVenueCard: View {
    @ObservedObject private var l10n = L10n.shared
    let venue: BarPassVenue

    /// Same call `recommendedForYou` scores with, so the badge shown here
    /// always matches the real reason this card ranked where it did — never
    /// independent, possibly-inconsistent copy.
    private var reasonText: String? {
        ExperienceScorer.reason(
            venue: venue,
            passport: MusicProfileStore.shared.passport,
            context: TripContext(),
            now: Date(),
            userCoordinate: UserLocationProvider.shared.coordinate
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: BPRadius.xl)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color.bpSurface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))

            Text(venue.emoji)
                .font(.bpScaled(72))
                .opacity(0.15)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)

            if let first = venue.photoUrls.first, let url = URL(string: first) {
                CachedImage(url: url, targetSize: CGSize(width: 400, height: 300), priority: .hot) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))
            }

            // Starts darkening higher up the card (not just from center) and
            // reaches near-opaque black — a photo this small can't rely on
            // "most real venue photos are already dark at the bottom." Bright
            // or busy photos (string lights, white decor) washed out the
            // text with the old .center/0.85 gradient.
            LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: UnitPoint(x: 0.5, y: 0.25), endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if venue.isTrending {
                        Text(l10n.t("tonight.trending.badge"))
                            .font(.bpTiny())
                            .tracking(2)
                            .foregroundStyle(Color.bpAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bpAmber.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3)))
                            .bpAccessibility(label: l10n.t("tonight.trending.a11y"), hint: l10n.t("tonight.trending.hint"))
                    }
                    if venue.hasHappyHour {
                        Text("HH")
                            .font(.bpTiny())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bpAmber, in: Capsule())
                            .bpAccessibility(label: l10n.t("tonight.hh.a11y"), hint: l10n.t("tonight.hh.hint"))
                    }
                }

                // This block sits on a hardcoded-dark photo scrim (line 458)
                // that doesn't change with app appearance — so its text must
                // always render light, never the theme-aware bpInk/
                // bpTextSecondary tokens (those go near-black in Light Mode,
                // which was unreadable against this permanently-dark card).
                Text(venue.name)
                    .font(.bpTitle2())
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Label(venue.neighborhood, systemImage: "location.fill")
                        .font(.bpSmall())
                        .foregroundStyle(.white.opacity(0.75))
                    Text("·").foregroundStyle(.white.opacity(0.5))
                    Label(venue.type.rawValue, systemImage: "music.note")
                        .font(.bpSmall())
                        .foregroundStyle(.white.opacity(0.75))
                }

                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.bpScaled(10))
                        .foregroundStyle(Color.bpAmber)
                    Text(String(format: "%.1f", venue.rating))
                        .font(.bpSmall()).fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(venue.priceTier.symbol ?? l10n.t("venue.crowd.na"))
                        .font(.bpSmall())
                        .foregroundStyle(.white.opacity(0.75))
                    // crowdBar removed — crowd_level is confirmed 100%
                    // "steady" for all 1,817 venues, no real live-busyness
                    // source, so the bar always showed the same fake
                    // reading for every card.
                }
            }
            .padding(16)
        }
        .frame(width: 280, height: 180)
        .overlay(alignment: .topLeading) {
            // Own opaque-ish background, independent of the photo gradient
            // below — top-leading sits above where that gradient darkens,
            // so this can't inherit the exact legibility bug just fixed for
            // the bottom text block.
            if let reasonText {
                Text(reasonText)
                    .font(.bpScaled(10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(10)
            }
        }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: venue.name, hint: String(format: l10n.t("tonight.venue.hint"), venue.neighborhood, venue.type.rawValue, venue.rating), isButton: true)
        .bpEntrance(offset: CGSize(width: 0, height: 20), delay: 0.1)
    }

}

// MARK: - Small Card

struct SmallVenueCard: View {
    @ObservedObject private var l10n = L10n.shared
    let venue: BarPassVenue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: BPRadius.lg)
                    .fill(Color.bpSurfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpInk.opacity(0.07)))
                    .frame(height: 100)

                if let first = venue.photoUrls.first, let url = URL(string: first) {
                    CachedImage(url: url, targetSize: CGSize(width: 200, height: 160), priority: .hot) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: BPRadius.lg))
                } else {
                    Text(venue.emoji)
                        .font(.bpScaled(44))
                        .opacity(0.2)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if venue.hasHappyHour, let until = venue.happyHourUntil {
                    Text("HH \(until)")
                        .font(.bpScaled(8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.bpAmber, in: Capsule())
                        .padding(6)
                        .bpAccessibility(label: String(format: l10n.t("tonight.hhUntil.a11y"), until))
                }
            }

            // TestFlight feedback: "cards are not well design they have ui
            // problems" — single-line truncation was chopping longer venue
            // names ("REPUBLICA FOOD & LIQUOR…") mid-word. Two lines with a
            // fixed height keeps the row aligned either way.
            Text(venue.name)
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 34, alignment: .top)

            Text(venue.neighborhood)
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.bpScaled(9))
                    .foregroundStyle(Color.bpAmber)
                Text(String(format: "%.1f", venue.rating))
                    .font(.bpSmall()).fontWeight(.semibold)
                    .foregroundStyle(Color.bpTextSecondary)
                Text("·").foregroundStyle(Color.bpTextTertiary)
                Text(venue.priceTier.symbol ?? l10n.t("venue.crowd.na"))
                    .font(.bpSmall())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: venue.name, hint: String(format: l10n.t("tonight.venueShort.hint"), venue.neighborhood, venue.rating), isButton: true)
        .bpEntrance(offset: CGSize(width: 0, height: 10), delay: 0.15)
    }
}

enum CardStyle { case hero, card }

#Preview {
    NavigationStack {
        TonightView()
            .environmentObject(VenueStore())
            .environmentObject(AppState())
    }
}
