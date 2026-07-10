import SwiftUI
import MapKit

struct ExploreView: View {
    @EnvironmentObject private var venueStore: VenueStore
    @State private var searchText = ""
    @State private var selectedLayer = "all"
    @State private var selectedVenue: BarPassVenue? = nil
    @State private var showList = false
    @State private var mapLoadTriggered = false
    @State private var cameraPosition: MapCameraPosition = .region(ExploreView.defaultRegion)
    @State private var visibleSpan: CLLocationDegrees = 0.08

    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.19),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private struct Cluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let venues: [BarPassVenue]
        var isSingle: Bool { venues.count == 1 }
    }

    private var clusters: [Cluster] {
        let cell = max(visibleSpan / 9, 0.0006)
        var buckets: [String: [BarPassVenue]] = [:]
        for v in filteredVenues where v.id != selectedVenue?.id {
            let gx = (v.latitude / cell).rounded(.down)
            let gy = (v.longitude / cell).rounded(.down)
            buckets["\(gx)_\(gy)", default: []].append(v)
        }
        return buckets.map { key, vs in
            let lat = vs.map(\.latitude).reduce(0, +) / Double(vs.count)
            let lng = vs.map(\.longitude).reduce(0, +) / Double(vs.count)
            return Cluster(id: key, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), venues: vs)
        }
    }

    private struct Layer: Identifiable {
        let id: String; let icon: String; let label: String
    }

    private let layers: [Layer] = [
        Layer(id: "all", icon: "square.grid.2x2", label: "All"),
        Layer(id: "trending", icon: "flame.fill", label: "Trending"),
        Layer(id: "happy_hour", icon: "clock.fill", label: "Happy Hour"),
        Layer(id: "no_cover", icon: "ticket.fill", label: "No Cover"),
        Layer(id: "rooftop", icon: "sun.max.fill", label: "Rooftops"),
        Layer(id: "live", icon: "music.mic", label: "Live Music"),
    ]

    private var filteredVenues: [BarPassVenue] {
        venueStore.venues.filter { v in
            let layerMatch: Bool = {
                switch selectedLayer {
                case "trending": return v.isTrending
                case "happy_hour": return v.hasHappyHour
                case "no_cover": return (v.coverMen ?? 1) == 0
                case "rooftop": return v.type == .rooftop
                case "live": return v.musicGenres.contains(.live)
                default: return true
                }
            }()
            guard layerMatch else { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return v.name.lowercased().contains(q) ||
                   v.neighborhood.lowercased().contains(q) ||
                   v.type.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            if showList {
                listView
                    .transition(.opacity)
            } else {
                mapView
                    .transition(.opacity)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Explorar")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        BPHaptics.light()
                        withAnimation(.spring(response: 0.3)) { showList.toggle() }
                    } label: {
                        Image(systemName: showList ? "map.fill" : "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                            .frame(width: 32, height: 32)
                            .glass(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, 60)

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bpTextTertiary)
                        TextField("", text: $searchText, prompt: Text("Buscar venues...").foregroundStyle(Color.bpTextTertiary))
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .tint(Color.bpAmber)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.bpTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glass(radius: BPRadius.xl)
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.white.opacity(0.06)))

                    Button {
                        showList = false
                        BPHaptics.medium()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                            .frame(width: 32, height: 32)
                            .glass(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(layers, id: \.id) { layer in
                            layerChip(layer)
                        }
                    }
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.vertical, 6)
                }

                Spacer()

                if !showList, let venue = selectedVenue {
                    venueCallout(venue)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 86)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35), value: selectedVenue?.id)
        .animation(.easeInOut(duration: 0.25), value: showList)
        .onAppear { mapLoadTriggered = true }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            ForEach(clusters) { cluster in
                Annotation(cluster.venues.first?.name ?? "", coordinate: cluster.coordinate) {
                    if cluster.isSingle, let venue = cluster.venues.first {
                        venueMarker(venue)
                            .onTapGesture {
                                BPHaptics.light()
                                withAnimation(.spring(response: 0.3)) {
                                    selectedVenue = selectedVenue?.id == venue.id ? nil : venue
                                }
                            }
                    } else {
                        clusterBubble(cluster)
                            .onTapGesture {
                                BPHaptics.light()
                                let span = max(visibleSpan / 2.5, 0.004)
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: cluster.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                                    ))
                                }
                            }
                    }
                }
                .annotationTitles(.hidden)
            }

            if let venue = selectedVenue {
                Annotation(venue.name, coordinate: venue.coordinate) {
                    venueMarker(venue)
                        .onTapGesture {
                            BPHaptics.light()
                            withAnimation(.spring(response: 0.3)) { selectedVenue = nil }
                        }
                }
                .annotationTitles(.hidden)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            visibleSpan = ctx.region.span.latitudeDelta
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
        }
    }

    private func clusterBubble(_ cluster: Cluster) -> some View {
        let n = cluster.venues.count
        let size: CGFloat = n >= 20 ? 54 : n >= 8 ? 46 : 40
        return Text("\(n)")
            .font(.system(size: size * 0.36, weight: .black))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.bpAmber))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
    }

    // MARK: - Marker

    private func venueMarker(_ venue: BarPassVenue) -> some View {
        let isSelected = selectedVenue?.id == venue.id
        let isTrending = venue.isTrending

        let size: CGFloat = isSelected ? 42 : 32

        return ZStack {
            Group {
                if let logo = VenueLogos.url(for: venue.id) {
                    ZStack {
                        Circle().fill(.white)
                        CachedImage(url: logo, targetSize: CGSize(width: 60, height: 60), priority: .hot) { img in
                            img.resizable().scaledToFit().padding(size * 0.16)
                        } placeholder: {
                            categoryPin(venue, size: size)
                        }
                    }
                } else {
                    categoryPin(venue, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(
                    isSelected ? Color.bpAmber : Color.white.opacity(0.8),
                    lineWidth: isSelected ? 2.5 : 1.5
                )
            )
            .shadow(color: isSelected ? Color.bpAmber.opacity(0.4) : .black.opacity(0.35), radius: isSelected ? 8 : 3, y: 1)

            if isTrending && !isSelected {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                    .offset(x: size * 0.4, y: -size * 0.4)
            }
        }
    }

    private func categoryPin(_ venue: BarPassVenue, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.bpCardBackground.opacity(0.96))
            Image(systemName: Self.markerIcon(venue.type))
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private static func markerIcon(_ type: VenueType) -> String {
        switch type {
        case .club:       return "music.note"
        case .rooftop:    return "building.2.fill"
        case .bar:        return "wineglass.fill"
        case .lounge:     return "sofa.fill"
        case .sportsBar:  return "sportscourt.fill"
        case .restaurant: return "fork.knife"
        case .brewery:    return "mug.fill"
        }
    }

    // MARK: - Callout

    private func venueCallout(_ venue: BarPassVenue) -> some View {
        NavigationLink(destination: VenueDetailView(venue: venue)) {
            HStack(spacing: 14) {
                Text(venue.emoji)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 3) {
                    Text(venue.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.bpAmber)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                        Text("·")
                            .foregroundStyle(Color.bpTextTertiary)
                        Text(venue.neighborhood)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bpTextSecondary)
                    }

                    HStack(spacing: 8) {
                        Text(venue.priceRange)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.bpTextSecondary)
                        if venue.isOpenNow {
                            Text("· Abierto")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.bpGreen)
                        }
                        if venue.isTrending {
                            Text("· 🔥 Trending")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.bpAmber)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.bpTextTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: BPRadius.lg)
                    .fill(Color.bpCardBackground.opacity(0.97))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BPRadius.lg)
                    .strokeBorder(Color.bpAmber.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chips

    private func layerChip(_ layer: Layer) -> some View {
        let selected = selectedLayer == layer.id
        return Button {
            BPHaptics.light()
            withAnimation(.spring(response: 0.3)) {
                selectedLayer = layer.id
                selectedVenue = nil
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: layer.icon).font(.system(size: 10))
                Text(layer.label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? .black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.bpAmber : Color.white.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(filteredVenues) { venue in
                    NavigationLink(destination: VenueDetailView(venue: venue)) {
                        VenueListRow(venue: venue)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.white.opacity(0.05)).padding(.leading, 76)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 120)
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 180) }
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.19),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }
}

// MARK: - Pulsing ring animation

struct PulsingRing: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.4

    var body: some View {
        Circle()
            .strokeBorder(Color.bpAmber.opacity(opacity), lineWidth: 1.5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.35
                    opacity = 0
                }
            }
    }
}

// MARK: - List Row

struct VenueListRow: View {
    let venue: BarPassVenue

    var body: some View {
        HStack(spacing: 14) {
            Text(venue.emoji)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(venue.neighborhood) · \(venue.type.rawValue)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bpTextSecondary)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color.bpAmber)
                    Text(String(format: "%.1f", venue.rating))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("·").foregroundStyle(Color.bpTextTertiary)
                    Text(venue.priceRange).font(.system(size: 12)).foregroundStyle(Color.bpTextSecondary)
                }
            }

            Spacer()

            if venue.isOpenNow {
                Text("Abierto")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.bpGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.bpGreen.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.vertical, 14)
    }
}
