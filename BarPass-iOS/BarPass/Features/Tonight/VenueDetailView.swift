import SwiftUI
import MapKit

struct VenueDetailView: View {
    let venue: BarPassVenue
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var isSaved = false
    @State private var showShareSheet = false
    @ObservedObject private var points = PointsEngine.shared
    @State private var checkinMessage: String?
    @State private var checkingIn = false

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

            ctaBar
        }
            .onAppear { BPAnalytics.track(.viewVenue(venue.id)) }
            .navigationBarHidden(true)
        .overlay(alignment: .topLeading) { navBar }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(venue: venue)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black],
                startPoint: .init(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(venue.vibes.prefix(4), id: \.self) { vibe in
            Text("#\(vibe)")
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Text(venue.name)
                .font(.bpLargeTitle())
                .foregroundStyle(.white)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Color.bpAmber)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Text("(\(venue.reviewCount))")
                            .font(.system(size: 12)).foregroundStyle(Color.bpTextSecondary)
                    }
                    Text("·").foregroundStyle(Color.bpTextTertiary)
                    Text(venue.type.rawValue)
                        .font(.system(size: 13)).foregroundStyle(Color.bpTextSecondary)
                    Text("·").foregroundStyle(Color.bpTextTertiary)
                    Text(venue.neighborhood)
                        .font(.system(size: 13)).foregroundStyle(Color.bpTextSecondary)
                }
            }
            .padding(.horizontal, BPSpacing.lg)
            .padding(.bottom, 20)
        }
        .frame(height: 300)
    }

    /// Real Google photo when available, emoji gradient as graceful fallback.
    @ViewBuilder private var heroBackground: some View {
        if let first = venue.photoUrls.first, let url = URL(string: first) {
            CachedImage(url: url, targetSize: CGSize(width: 420, height: 420), priority: .hot) { image in
                // Color.clear adopts the PROPOSED size; the overlaid fill image
                // is then clipped to it. A bare scaledToFill here reports the
                // bitmap's ideal width (~1260pt) and blows the whole screen
                // layout sideways.
                Color.clear
                    .overlay(image.resizable().scaledToFill())
                    .clipped()
            } placeholder: {
                ZStack {
                    heroEmojiFallback
                    ProgressView().tint(Color.bpAmber)
                }
            }
        } else {
            heroEmojiFallback
        }
    }

    private var heroEmojiFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(venue.emoji).font(.system(size: 120)).opacity(0.12)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            quickStats
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, 20)

            divider

            timingSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            // AI Insight — prominent position
            aiInsightSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            musicSection
                .padding(.horizontal, BPSpacing.lg)

            if !venue.popularDrinks.isEmpty {
                divider
                drinksSection
                    .padding(.horizontal, BPSpacing.lg)
            }

            if !venue.upcomingEvents.isEmpty {
                divider
                eventsSection
                    .padding(.horizontal, BPSpacing.lg)
            }

            if !venue.photoUrls.isEmpty {
                divider
                photosSection
            }

            divider

            reviewsSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            VenuePostsSection(venue: venue)
                .padding(.horizontal, BPSpacing.lg)

            divider

            locationSection
                .padding(.horizontal, BPSpacing.lg)
        }
    }

    // MARK: - Quick stats

    private var quickStats: some View {
        HStack(spacing: 0) {
            quickStat(icon: "clock.fill", label: "Cierra", value: venue.closeTime, primary: true)
            Divider().background(Color.white.opacity(0.08)).frame(height: 40)
            quickStat(icon: "ticket.fill", label: "Cover", value: venue.priceRange, primary: false)
            Divider().background(Color.white.opacity(0.08)).frame(height: 40)
            quickStat(icon: "person.3.fill", label: "Crowd", value: venue.crowdDescription, primary: false)
        }
        .padding(.vertical, 14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.07)))
    }

    private func quickStat(icon: String, label: String, value: String, primary: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: primary ? 18 : 14))
                .foregroundStyle(Color.bpAmber)
            Text(value)
                .font(.system(size: primary ? 16 : 13, weight: primary ? .black : .bold))
                .foregroundStyle(primary ? Color.bpAmber : .white)
            Text(label)
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Cuándo ir")

            infoRow("calendar", "Horario", "\(venue.openTime) – \(venue.closeTime)")
            infoRow("clock.arrow.2.circlepath", "Mejor hora", venue.bestArrivalTime)
            infoRow("waveform.path.ecg", "Peak hours", venue.peakHours)
            infoRow("dollarsign.circle.fill", "Gasto prom.", venue.avgSpend + " / persona")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Crowd")
                        .font(.system(size: 13)).foregroundStyle(Color.bpTextSecondary)
                    Spacer()
                    Text(venue.crowdDescription)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < venue.crowdLevel ? Color.bpAmber : Color.white.opacity(0.1))
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.bpAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.bpAmber.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.2)))
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
                            .foregroundStyle(Color.bpAmber)
                    }
                    .bpAccessibility(label: "\(drink.name), \(String(format: "$%.0f", drink.price))", hint: "Bebida popular en este venue")
                }
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Próximos eventos")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(venue.upcomingEvents.sorted { $0.date < $1.date }) { event in
                        EventFlyerCard(event: event, venue: venue, width: 190, height: 250)
                    }
                }
            }
        }
    }

    // MARK: - Photos (real Google photos via venue_media.json)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Fotos")
                .padding(.horizontal, BPSpacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(venue.photoUrls, id: \.self) { urlString in
                        AsyncImage(url: URL(string: urlString)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .empty:
                                ZStack {
                                    Color(white: 0.08)
                                    ProgressView().tint(Color.bpAmber)
                                }
                            case .failure:
                                ZStack {
                                    Color(white: 0.08)
                                    Image(systemName: "photo")
                                        .foregroundStyle(Color.bpTextSecondary)
                                }
                            @unknown default:
                                Color(white: 0.08)
                            }
                        }
                        .frame(width: 260, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: BPRadius.md))
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    // MARK: - Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Reviews")

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.bpAmber)
                Text(String(format: "%.1f", venue.rating))
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                Text("(\(venue.reviewCount) reviews)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bpTextSecondary)
                Spacer()
            }

            Text("Rating de Google")
                .font(.system(size: 11))
                .foregroundStyle(Color.bpTextSecondary.opacity(0.7))

            xpActions
        }
    }

    // MARK: - XP actions (check-in por proximidad + review)

    private var xpActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: attemptCheckIn) {
                    HStack(spacing: 6) {
                        if checkingIn { ProgressView().tint(.black).scaleEffect(0.7) }
                        else { Image(systemName: points.hasCheckedInToday(venueId: venue.id) ? "checkmark.seal.fill" : "mappin.and.ellipse").font(.system(size: 13)) }
                        Text(points.hasCheckedInToday(venueId: venue.id) ? "Check-in hecho" : "Check-in · +50 XP")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(points.hasCheckedInToday(venueId: venue.id) ? Color.bpGreen : .black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(points.hasCheckedInToday(venueId: venue.id) ? Color.bpGreen.opacity(0.12) : Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(checkingIn || points.hasCheckedInToday(venueId: venue.id))
                .bpAccessibility(label: "Check-in", hint: "Registrar tu visita a este venue y ganar 50 XP", isButton: true)

                Button {
                    if points.leaveReview(venueId: venue.id) != nil {
                        checkinMessage = "+75 XP · ¡Gracias por tu review!"
                    } else {
                        checkinMessage = "Ya dejaste review de este lugar."
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: points.hasReviewed(venueId: venue.id) ? "star.fill" : "square.and.pencil").font(.system(size: 13))
                        Text(points.hasReviewed(venueId: venue.id) ? "Review dejada" : "Dejar review · +75 XP")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(points.hasReviewed(venueId: venue.id) ? Color.bpGreen : Color.bpAmber)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.bpAmber.opacity(points.hasReviewed(venueId: venue.id) ? 0.06 : 0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(points.hasReviewed(venueId: venue.id))
                .bpAccessibility(label: "Dejar review", hint: "Dejar una review y ganar 75 XP", isButton: true)
            }

            if let msg = checkinMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                    .transition(.opacity)
            }
        }
        .padding(.top, 6)
    }

    private func attemptCheckIn() {
        checkingIn = true
        checkinMessage = nil
        Task {
            let service = LocationService()
            let coord = await service.requestOnce()
            await MainActor.run {
                checkingIn = false
                guard let coord else {
                    checkinMessage = "Activá la ubicación para hacer check-in."
                    return
                }
                let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let there = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
                let meters = here.distance(from: there)
                if meters <= 250 {
                    if points.checkIn(venueId: venue.id) != nil {
                        withAnimation { checkinMessage = "+50 XP · ¡Estás en \(venue.name)!" }
                    }
                } else {
                    withAnimation { checkinMessage = "Estás a \(Int(meters)) m — acercate para el check-in." }
                }
            }
        }
    }

    // MARK: - AI Insight

    private var aiInsightSection: some View {
        ReviewSummaryView(venue: venue)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Cómo llegar")
            infoRow("location.fill", "Dirección", venue.address)
            infoRow("car.fill", "Parking", venue.parking)

            HStack(spacing: 10) {
                linkButton(icon: "map.fill", label: "Maps") { openMaps() }
                linkButton(icon: "car.fill", label: "Uber") { openUber() }
                if let ig = venue.instagramHandle {
                    linkButton(icon: "camera.fill", label: "@\(ig)") { openInstagram(handle: ig) }
                }
            }
        }
    }

    // MARK: - CTA Bar

    private var ctaBar: some View {
        HStack(spacing: 10) {
            Button {
                BPHaptics.light()
                withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
            } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(isSaved ? Color.bpDanger : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Guardar", hint: "Guardar o quitar de favoritos", isButton: true)

            Button {
                appState.priorityVenueId = venue.id
                appState.priorityVenueName = venue.name
                appState.showPriorityEntry = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 12))
                    Text("Skip the Line")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: BPRadius.md)
                )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Skip the Line", hint: "Comprar acceso prioritario sin fila", isButton: true)

            Button {
                BPAnalytics.track(.openMaps(venue: venue.name))
                let coords = "\(venue.latitude),\(venue.longitude)"
                guard let url = URL(string: "https://maps.apple.com/?ll=\(coords)&q=\(venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.bpAmber)
                    .frame(width: 48, height: 48)
                    .background(Color.bpAmber.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Direcciones", hint: "Abrir ubicación en Mapas", isButton: true)
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.vertical, 10)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button { BPHaptics.light(); dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Volver", hint: "Volver a la pantalla anterior", isButton: true)
            Spacer()
            Button { BPHaptics.light(); showShareSheet = true; BPAnalytics.track(.shareVenue(venue: venue.id)); PointsEngine.shared.award(.shareVenue) } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Compartir", hint: "Compartir este venue", isButton: true)
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.top, 56)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, BPSpacing.lg)
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
                .foregroundStyle(Color.bpAmber)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.bpTextSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private func linkButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.sm).strokeBorder(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: "Abrir en \(label)", isButton: true)
    }

    // MARK: - Actions

    private func openMaps() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = venue.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openUber() {
        let encoded = venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let uberURL = URL(string: "uber://?action=setPickup&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)&dropoff[nickname]=\(encoded)")
        if let url = uberURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://m.uber.com/ul/?action=setPickup&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)") {
            UIApplication.shared.open(url)
        }
    }

    private func openInstagram(handle: String) {
        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: "instagram://user?username=\(cleanHandle)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://instagram.com/\(cleanHandle)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let venue: BarPassVenue

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let text = "Check out \(venue.name) in Miami! \(venue.neighborhood)"
        guard let url = URL(string: "https://barpass.app/venues/\(venue.id)") else {
            return UIActivityViewController(activityItems: [text], applicationActivities: nil)
        }
        return UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        VenueDetailView(venue: BarPassVenue.preview)
    }
}
