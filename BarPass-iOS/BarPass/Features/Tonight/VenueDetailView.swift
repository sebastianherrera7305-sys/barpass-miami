import SwiftUI

struct VenueDetailView: View {
    let venue: Venue
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                        .padding(.bottom, 100)
                }
            }
            .ignoresSafeArea(edges: .top)

            // CTA bar
            ctaBar
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) { navBar }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background (placeholder for real photo)
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 300)

            // Emoji large
            Text(venue.emoji)
                .font(.system(size: 120))
                .opacity(0.12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // Gradient fade
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .init(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .frame(height: 300)

            // Venue info
            VStack(alignment: .leading, spacing: 8) {
                // Vibes
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(venue.vibes.prefix(4), id: \.self) { vibe in
                            Text("#\(vibe)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Text(venue.name)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(amber)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Text("(\(venue.reviewCount))")
                            .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4))
                    }
                    Text("·").foregroundStyle(Color.white.opacity(0.2))
                    Text(venue.type.rawValue)
                        .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
                    Text("·").foregroundStyle(Color.white.opacity(0.2))
                    Text(venue.neighborhood)
                        .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 300)
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Quick stats row
            quickStats
                .padding(.horizontal, 20)
                .padding(.top, 20)

            divider

            // Crowd & timing
            timingSection
                .padding(.horizontal, 20)

            divider

            // Music
            musicSection
                .padding(.horizontal, 20)

            // Popular drinks
            if !venue.popularDrinks.isEmpty {
                divider
                drinksSection
                    .padding(.horizontal, 20)
            }

            // Upcoming events
            if !venue.upcomingEvents.isEmpty {
                divider
                eventsSection
                    .padding(.horizontal, 20)
            }

            divider

            // AI Insight
            aiInsightSection
                .padding(.horizontal, 20)

            divider

            // Location
            locationSection
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Quick stats

    private var quickStats: some View {
        HStack(spacing: 0) {
            quickStat(icon: "clock.fill", label: "Cierra", value: venue.closeTime)
            Divider().background(Color.white.opacity(0.08)).frame(height: 40)
            quickStat(icon: "ticket.fill", label: "Cover", value: venue.priceRange)
            Divider().background(Color.white.opacity(0.08)).frame(height: 40)
            quickStat(icon: "person.3.fill", label: "Crowd", value: venue.crowdDescription)
        }
        .padding(.vertical, 14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.07)))
    }

    private func quickStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(amber)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Cuándo ir")

            infoRow("calendar", "Horario", "\(venue.openTime) – \(venue.closeTime)")
            infoRow("clock.arrow.2.circlepath", "Mejor hora de llegar", venue.bestArrivalTime)
            infoRow("waveform.path.ecg", "Peak hours", venue.peakHours)
            infoRow("dollarsign.circle.fill", "Gasto promedio", venue.avgSpend + " / persona")

            // Crowd bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nivel de crowd")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Spacer()
                    Text(venue.crowdDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < venue.crowdLevel ? amber : Color.white.opacity(0.1))
                            .frame(height: 8)
                    }
                }
            }
        }
    }

    // MARK: - Music

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Música & Ambiente")
            HStack(spacing: 8) {
                ForEach(venue.musicGenres, id: \.self) { genre in
                    Text(genre.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(amber.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(amber.opacity(0.2)))
                }
            }
            infoRow("tshirt.fill", "Dress Code", venue.dressCode)
        }
    }

    // MARK: - Drinks

    private var drinksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Bebidas populares")
            VStack(spacing: 10) {
                ForEach(venue.popularDrinks) { drink in
                    HStack {
                        Text(drink.emoji).font(.system(size: 22))
                        Text(drink.name)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "$%.0f", drink.price))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(amber)
                    }
                }
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Próximos eventos")
            VStack(spacing: 10) {
                ForEach(venue.upcomingEvents) { event in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(event.date, style: .date)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        Spacer()
                        if let cover = event.coverPrice {
                            Text(cover == 0 ? "Gratis" : String(format: "$%.0f", cover))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(cover == 0 ? Color(red: 0.2, green: 0.9, blue: 0.4) : amber)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - AI Insight

    private var aiInsightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(amber)
                Text("AI Insight").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            Text("Mejor momento para ir: \(venue.bestArrivalTime). \(venue.type == .club ? "Llega con lista para evitar el cover." : "Ambiente más tranquilo entre semana.") Dress code: \(venue.dressCode).")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineSpacing(4)
        }
        .padding(16)
        .background(amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(amber.opacity(0.15)))
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Cómo llegar")
            infoRow("location.fill",    "Dirección", venue.address)
            infoRow("car.fill",         "Parking",   venue.parking)

            HStack(spacing: 10) {
                linkButton(icon: "map.fill",     label: "Maps")
                linkButton(icon: "car.fill",     label: "Uber")
                if let ig = venue.instagramHandle {
                    linkButton(icon: "camera.fill", label: "@\(ig)")
                }
            }
        }
    }

    // MARK: - CTA Bar

    private var ctaBar: some View {
        HStack(spacing: 12) {
            // Save button
            Button {
                withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
            } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundStyle(isSaved ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            // Check in
            Button { } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 16))
                    Text("Check-in · +50 BPX")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(amber)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private func linkButton(icon: String, label: String) -> some View {
        Button { } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        VenueDetailView(venue: VenueStore.miamVenues[0])
    }
}
