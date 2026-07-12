import SwiftUI

struct TonightView: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var selectedTag: String? = nil

    /// Mood Mode — browse by experience, not venue type. Each mood maps to
    /// keywords matched against type/vibes/tags/music (same approach as
    /// NightPlanner) so selection actually filters the feed.
    private struct Mood: Hashable {
        let label: String
        let keywords: [String]
    }

    private let moods: [Mood] = [
        .init(label: "🔥 Trending",   keywords: ["trending"]),
        .init(label: "🎉 Party",      keywords: ["club", "edm", "house", "techno", "packed", "reggaeton"]),
        .init(label: "🍸 Cocktails",  keywords: ["cocktail", "lounge", "bar", "mixology"]),
        .init(label: "🥂 Date Night", keywords: ["date", "romantic", "rooftop", "lounge", "upscale", "views", "restaurant"]),
        .init(label: "🍽️ Dinner",     keywords: ["restaurant", "dinner", "food"]),
        .init(label: "🎵 Live Music", keywords: ["live", "jazz", "salsa", "latin", "band"]),
        .init(label: "🌇 Rooftop",    keywords: ["rooftop", "sunset", "views", "terrace"]),
        .init(label: "🏈 Sports",     keywords: ["sports", "sport", "game", "screens"]),
    ]

    private func matches(_ venue: BarPassVenue, _ mood: Mood) -> Bool {
        if mood.label.contains("Trending") { return venue.isTrending }
        let haystack = ([venue.type.rawValue, venue.name] + venue.vibes + venue.tags
            + venue.musicGenres.map { $0.rawValue }).joined(separator: " ").lowercased()
        return mood.keywords.contains { haystack.contains($0) }
    }

    private var favoriteVenues: [BarPassVenue] {
        venueStore.venues.filter { favorites.ids.contains($0.id) }
    }

    private var moodVenues: [BarPassVenue] {
        guard let tag = selectedTag, let mood = moods.first(where: { $0.label == tag }) else { return [] }
        return venueStore.venues.filter { matches($0, mood) }
            .sorted { ($0.isTrending ? 1 : 0, $0.rating) > ($1.isTrending ? 1 : 0, $1.rating) }
    }

    var body: some View {
        ZStack {
            Color.bpBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: BPSpacing.xl) {
                    header
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.top, 60)

                    vibeTags

                    if venueStore.isLoading {
                        skeletonContent
                    } else if let tag = selectedTag {
                        // Mood Mode: the selected experience takes over the feed.
                        if moodVenues.isEmpty {
                            VStack(spacing: 8) {
                                Text("😴").font(.system(size: 40))
                                Text("Nada abierto con ese mood ahora.")
                                    .font(.system(size: 14)).foregroundStyle(Color.bpTextSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else {
                            section(title: "\(tag) · \(moodVenues.count) lugares",
                                    venues: Array(moodVenues.prefix(3)), style: .hero)
                            if moodVenues.count > 3 {
                                section(title: "Más para este mood",
                                        venues: Array(moodVenues.dropFirst(3).prefix(12)), style: .card)
                            }
                        }
                    } else {
                        if !favoriteVenues.isEmpty {
                            section(title: "❤️ Tus favoritos", venues: favoriteVenues, style: .card)
                        }

                        if !tonightEvents.isEmpty {
                            eventsTonightSection
                        }

                        if !venueStore.trending.isEmpty {
                            section(title: "🔥 Trending ahora", venues: venueStore.trending, style: .hero)
                        }

                        if !venueStore.happyHour.isEmpty {
                            section(title: "🍹 Happy Hour activo", venues: venueStore.happyHour, style: .card)
                        }

                        if !venueStore.openNow.isEmpty {
                            section(title: "⚡ Abiertos ahora", venues: venueStore.openNow, style: .card)
                        }

                        neighborhoodSection("Brickell")
                        neighborhoodSection("South Beach")
                        neighborhoodSection("Wynwood")
                    }

                    Spacer(minLength: 120)
                }
            }
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BarPassLogo(subtitle: "MIAMI")
                .padding(.bottom, 4)

            Text(greeting)
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)

            Text(l10n.t("home.where"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .bpAccessibility(label: greeting, hint: "Bienvenido a BarPass. ¿A dónde quieres ir esta noche?")
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedTag == tag ? .black : .white)
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
                    .bpAccessibility(label: tag, hint: "Filtrar venues por esta categoría", isButton: true)
                }
            }
            .padding(.horizontal, BPSpacing.lg)
        }
    }

    // MARK: - Events tonight (flyer rail)

    /// Events starting within the next 36 hours, paired with their venue.
    private var tonightEvents: [(event: VenueEvent, venue: BarPassVenue)] {
        let now = Date()
        let horizon = now.addingTimeInterval(36 * 3600)
        return venueStore.venues
            .flatMap { v in v.upcomingEvents.map { (event: $0, venue: v) } }
            .filter { $0.event.date > now.addingTimeInterval(-6 * 3600) && $0.event.date < horizon }
            .sorted { $0.event.date < $1.event.date }
    }

    private var eventsTonightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🎟️ Esta noche")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, BPSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(tonightEvents, id: \.event.id) { pair in
                        NavigationLink(destination: VenueDetailView(venue: pair.venue)) {
                            EventFlyerCard(event: pair.event, venue: pair.venue)
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: "\(pair.event.title) en \(pair.venue.name)", hint: "Ver detalle del evento", isButton: true)
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    // MARK: - Sections

    private func section(title: String, venues: [BarPassVenue], style: CardStyle) -> some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            Text(title)
                .font(.bpHeadline())
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, BPSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BPSpacing.md) {
                    ForEach(venues) { venue in
                        NavigationLink(destination: VenueDetailView(venue: venue)) {
                            switch style {
                            case .hero: HeroVenueCard(venue: venue)
                            case .card: SmallVenueCard(venue: venue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    private func neighborhoodSection(_ neighborhood: String) -> some View {
        let filtered = venueStore.venues.filter { $0.neighborhood == neighborhood }
        guard !filtered.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(section(title: "📍 \(neighborhood)", venues: filtered, style: .card))
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
    let venue: BarPassVenue

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: BPRadius.xl)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color.bpSurface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))

            Text(venue.emoji)
                .font(.system(size: 72))
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

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if venue.isTrending {
                        Text("TRENDING")
                            .font(.bpTiny())
                            .tracking(2)
                            .foregroundStyle(Color.bpAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bpAmber.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3)))
                            .bpAccessibility(label: "Tendencia", hint: "Este venue está trending")
                    }
                    if venue.hasHappyHour {
                        Text("HH")
                            .font(.bpTiny())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bpAmber, in: Capsule())
                            .bpAccessibility(label: "Happy hour", hint: "Happy hour activo")
                    }
                }

                Text(venue.name)
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)

                HStack(spacing: 10) {
                    Label(venue.neighborhood, systemImage: "location.fill")
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("·").foregroundStyle(Color.bpTextTertiary)
                    Label(venue.type.rawValue, systemImage: "music.note")
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextSecondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.bpAmber)
                    Text(String(format: "%.1f", venue.rating))
                        .font(.bpSmall()).fontWeight(.semibold)
                        .foregroundStyle(Color.bpInk)
                    Text(venue.priceRange)
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextSecondary)
                    crowdBar
                }
            }
            .padding(16)
        }
        .frame(width: 280, height: 180)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: venue.name, hint: "Venue: \(venue.neighborhood). \(venue.type.rawValue). Puntuación: \(venue.rating)", isButton: true)
        .bpEntrance(offset: CGSize(width: 0, height: 20), delay: 0.1)
    }

    private var crowdBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < venue.crowdLevel ? Color.bpAmber : Color.bpInk.opacity(0.15))
                    .frame(width: 3, height: 8)
            }
        }
    }
}

// MARK: - Small Card

struct SmallVenueCard: View {
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
                        .font(.system(size: 44))
                        .opacity(0.2)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if venue.hasHappyHour, let until = venue.happyHourUntil {
                    Text("HH \(until)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.bpAmber, in: Capsule())
                        .padding(6)
                        .bpAccessibility(label: "Happy hour hasta las \(until)")
                }
            }

            Text(venue.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .lineLimit(1)

            Text(venue.neighborhood)
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.bpAmber)
                Text(String(format: "%.1f", venue.rating))
                    .font(.bpSmall()).fontWeight(.semibold)
                    .foregroundStyle(Color.bpTextSecondary)
                Text("·").foregroundStyle(Color.bpTextTertiary)
                Text(venue.priceRange)
                    .font(.bpSmall())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: venue.name, hint: "\(venue.neighborhood). Puntuación: \(venue.rating)", isButton: true)
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
