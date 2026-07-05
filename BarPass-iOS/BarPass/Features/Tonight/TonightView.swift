import SwiftUI

struct TonightView: View {
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var selectedTag: String? = nil

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    private let discoveryTags = [
        "🔥 Trending", "🍹 Happy Hour", "🎵 EDM",
        "💃 Latin", "🌇 Rooftop", "🏀 Sports",
        "💎 VIP", "🎨 Wynwood", "👫 Date Night",
        "🌙 Late Night", "🎂 Celebrar", "No Cover"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {

                    // Header
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                    // Vibe tags scroll
                    vibeTags

                    // Trending now
                    if !venueStore.trending.isEmpty {
                        section(title: "🔥 Trending ahora", venues: venueStore.trending, style: .hero)
                    }

                    // Happy hour active
                    if !venueStore.happyHour.isEmpty {
                        section(title: "🍹 Happy Hour activo", venues: venueStore.happyHour, style: .card)
                    }

                    // Open now
                    section(title: "⚡ Abiertos ahora", venues: venueStore.openNow, style: .card)

                    // By neighborhood
                    neighborhoodSection(neighborhood: "Brickell")
                    neighborhoodSection(neighborhood: "South Beach")
                    neighborhoodSection(neighborhood: "Wynwood")

                    Spacer(minLength: 120)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .tracking(1)

            Text("¿A dónde esta noche?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(amber)
                Text("Miami, FL")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    // MARK: - Vibe tags

    private var vibeTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(discoveryTags, id: \.self) { tag in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    } label: {
                        Text(tag)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTag == tag ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTag == tag
                                          ? LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing)
                                          : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selectedTag == tag ? Color.clear : Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Section builders

    private func section(title: String, venues: [Venue], style: CardStyle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
                .padding(.horizontal, 20)
            }
        }
    }

    private func neighborhoodSection(neighborhood: String) -> some View {
        let filtered = venueStore.venues.filter { $0.neighborhood == neighborhood }
        guard !filtered.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(section(title: "📍 \(neighborhood)", venues: filtered, style: .card))
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "BUENOS DÍAS"
        case 12..<18: return "BUENAS TARDES"
        default: return "BUENAS NOCHES"
        }
    }
}

enum CardStyle { case hero, card }

// MARK: - Hero Card

struct HeroVenueCard: View {
    let venue: Venue
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background gradient (placeholder until real photos)
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.07))
                )

            // Emoji art
            Text(venue.emoji)
                .font(.system(size: 80))
                .opacity(0.15)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .cornerRadius(20)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                if venue.isTrending {
                    Text("TRENDING")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(amber.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(amber.opacity(0.3)))
                }

                Text(venue.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Label(venue.neighborhood, systemImage: "location.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))

                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))

                    Label(venue.type.rawValue, systemImage: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                HStack(spacing: 8) {
                    // Rating
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(amber)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    // Cover
                    Text(venue.priceRange)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))

                    // Crowd
                    crowdBadge
                }
            }
            .padding(16)
        }
        .frame(width: 280, height: 180)
    }

    private var crowdBadge: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < venue.crowdLevel ? amber : Color.white.opacity(0.15))
                    .frame(width: 4, height: 10)
            }
        }
    }
}

// MARK: - Small Card

struct SmallVenueCard: View {
    let venue: Venue
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top area
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.07)))
                    .frame(height: 110)

                Text(venue.emoji)
                    .font(.system(size: 50))
                    .opacity(0.2)
                    .padding(12)

                // Happy hour badge
                if venue.hasHappyHour, let until = venue.happyHourUntil {
                    Text("HH hasta \(until)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(amber, in: Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(venue.neighborhood)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(amber)
                    Text(String(format: "%.1f", venue.rating))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text(venue.priceRange)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .frame(width: 160)
    }
}

#Preview {
    NavigationStack {
        TonightView()
            .environmentObject(VenueStore())
            .environmentObject(AppState())
    }
}
