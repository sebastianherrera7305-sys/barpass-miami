import SwiftUI

// ExploreV2View — Pantalla "Explore" del artifact v17.1 (sección "Tabs",
// líneas 611-740 del HTML). Mapa estilizado de la ciudad con pines en vivo,
// búsqueda, capas (Trending / Happy Hour / Rooftops / Música en vivo) y la
// tarjeta del venue tocado.
//
// Match de estilo con OnboardingV2Flow.swift y RemyLiveView.swift: fondo
// Miami eye + warm vignette + fade mask + grain, tipografía black rounded
// + serif italic + mono tracked, cards Color.white.opacity(0.04) con stroke
// 0.08, acento Color.bpAmber / bpAmberBright.
//
// Data wiring (2026-10-10): los pines, el contador y el callout salen de
// `VenueStore` — ya no son literales del mockup. Tap en un pin o en "Ver
// venue" abre `VenueDetailView` (V1), mismo wiring que usa el deep-link y
// la V1 de Explore. El `selectedLayer` filtra la lista de pines con el
// mismo criterio que `ExploreView.filteredVenues` (isTrending, hasHappyHour,
// type==.rooftop, musicGenres.contains(.live)).
//
// Segundo pase (2026-10-11): nada del canvas es literal ya.
// - Buscador real (`searchText`) que filtra pines, callout y lista por
//   nombre / barrio / tipo, sin distinguir mayúsculas ni acentos — mismos
//   campos que `ExploreView.filteredVenues` (V1).
// - El toggle Mapa / Lista funciona: Lista renderiza las filas del callout
//   para todos los venues filtrados.
// - Las etiquetas de barrio salen de los `neighborhood` más frecuentes de la
//   ciudad (centroide de sus venues en el mismo bbox que los pines); el
//   chip "N abiertos ahora" cuenta `isOpenNow` del set filtrado; el punto
//   "me" sólo se dibuja si `UserLocationProvider` tiene una coordenada y cae
//   dentro del bbox; el cluster "+N" se ubica en el centroide de los venues
//   que esconde.
//
// Limitaciones conocidas (fuera de este pase):
// - El mapa sigue siendo un canvas estilizado (grid de calles + wedge de
//   agua + pines absolutos), no MapKit. Un mapa nativo con tiles custom
//   entra en un pase siguiente. El botón "scope" resetea filtros, búsqueda y
//   selección (no hay pan/zoom que recentrar).
// - Topamos los pines a 15 por pantalla porque el canvas de 300pt se
//   satura rápido pasado ese número; el resto se agrega al cluster "+N".

@MainActor
struct ExploreV2View: View {
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState: AppState
    /// Same feed SocialV2 renders (RPC `get_friends_out_tonight`). Drives the
    /// friends strip; the mockup's "Mía, Jules y Dani" were literals.
    @ObservedObject private var tonight = FriendsTonightStore.shared
    /// Ubicación real del usuario (una sola fix por sesión, compartida con
    /// Tonight). `coordinate == nil` si nunca dio permiso → no hay punto "me".
    @ObservedObject private var location = UserLocationProvider.shared

    @State private var viewMode: ExploreV2ViewMode = .map
    @State private var selectedLayer: ExploreV2Layer = .all
    @State private var selectedPinID: String? = nil
    @State private var searchText: String = ""
    /// El venue abierto en el sheet (`VenueDetailView` de V1). Mismo patrón
    /// que `TripsListV2View.selectedTrip` → `TripDetailView` sheet.
    @State private var selectedVenue: BarPassVenue? = nil

    /// Más de 15 pines sobre 300pt de alto empieza a verse como ruido. El
    /// resto va al chip "+N" del cluster.
    private static let maxVisiblePins = 15

    var body: some View {
        ZStack {
            ExploreV2Background()

            VStack(spacing: 0) {
                // iOS pinta el status bar real; el header conserva el aire
                // superior que el mockup tenía debajo del suyo.
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                        searchField
                            .padding(.horizontal, 20)

                        layerStrip
                            .padding(.horizontal, 20)

                        friendsStrip
                            .padding(.horizontal, 20)

                        if viewMode == .map {
                            mapCanvas
                                .padding(.horizontal, 20)
                                .padding(.top, 2)

                            tappedCallout
                                .padding(.horizontal, 20)
                                .padding(.top, 2)
                        } else {
                            venueList
                                .padding(.horizontal, 20)
                                .padding(.top, 2)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 40)
                }
                // Pull-to-refresh: lets the user recover from the
                // `FriendsTonightStore` 60s short-circuit and re-ask the
                // catalogue in one gesture.
                .refreshable {
                    await venueStore.loadVenues()
                    await tonight.refresh(force: true)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            location.refreshOnce()
            // `loadVenues()` is idempotent per its own doc: if MainTabView
            // already fetched before the user hit this tab, this is a
            // cheap no-op; if the user opened the app straight on Explore
            // we still fill the screen instead of showing the empty shell.
            await venueStore.loadVenues()
            await tonight.refresh(force: false)
        }
        .sheet(item: $selectedVenue) { venue in
            NavigationStack {
                VenueDetailView(venue: venue).appState(appState)
            }
            .presentationDetents([.large])
            .presentationBackground(.black)
        }
    }

    // MARK: - Data derivation

    /// La ciudad entera (sin filtro de capa) — se usa para anclar los pines
    /// a un bbox estable: cambiar entre capas NO debe mover los que ya están
    /// en pantalla, sólo ocultar los que ya no entran.
    private var cityVenues: [BarPassVenue] { venueStore.venues }

    /// Separa "no hay nada que mostrar porque VenueStore todavía está
    /// trayendo" / "falló la carga" / "la ciudad no tiene nada en esta capa".
    /// Antes la pantalla contestaba igual los tres casos ("Sin venues para
    /// esta capa · Toca otra capa") y escondía la causa real detrás de un
    /// mensaje mentiroso.
    private enum StoreState {
        /// Primer frame del launch: el store está trayendo venues y
        /// todavía no entregó ninguno.
        case loading
        /// La red o la query fallaron ANTES de que llegara el primer
        /// venue (ya con venues en pantalla el error es un detalle, no
        /// un bloqueo).
        case error(String)
        /// Hay venues cargados — el filtro de capa o la búsqueda es lo
        /// que decide si el callout muestra algo o "Toca otra capa".
        case ready
    }

    private var storeState: StoreState {
        if !cityVenues.isEmpty { return .ready }
        if venueStore.isLoading { return .loading }
        if let err = venueStore.loadError { return .error(err) }
        // Store terminó de cargar sin error pero sin resultados — tratarlo
        // como ready con filtro vacío es honesto; "Sin venues para esta
        // capa" ya dice lo correcto.
        return .ready
    }

    /// Match 1-a-1 con `ExploreView.filteredVenues` (V1), para que las dos
    /// capas de la app contesten lo mismo si alguien toca el mismo chip.
    private var layerFilteredVenues: [BarPassVenue] {
        switch selectedLayer {
        case .all:       return cityVenues
        case .trending:  return cityVenues.filter { $0.isTrending }
        case .happyHour: return cityVenues.filter { $0.hasHappyHour }
        case .rooftops:  return cityVenues.filter { $0.type == .rooftop }
        case .liveMusic: return cityVenues.filter { $0.musicGenres.contains(.live) }
        }
    }

    /// Capa + buscador. Mismos campos que `ExploreView.filteredVenues` (V1):
    /// nombre, barrio, `type.rawValue` y `type.displayName`, sin distinguir
    /// mayúsculas ni acentos ("cafe" encuentra "Café").
    private var filteredVenues: [BarPassVenue] {
        let q = Self.searchKey(searchText)
        guard !q.isEmpty else { return layerFilteredVenues }
        return layerFilteredVenues.filter { v in
            Self.searchKey(v.name).contains(q) ||
            Self.searchKey(v.neighborhood).contains(q) ||
            Self.searchKey(v.type.rawValue).contains(q) ||
            Self.searchKey(v.type.displayName).contains(q)
        }
    }

    private static func searchKey(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trending primero, después por rating. "Mostrar los más interesantes
    /// antes" se nota mucho en Trending (pocos venues) y en All (muchos
    /// venues → el top-15 del canvas debe ser el que vale la pena ver).
    private var rankedVenues: [BarPassVenue] {
        filteredVenues.sorted { lhs, rhs in
            if lhs.isTrending != rhs.isTrending { return lhs.isTrending }
            return lhs.rating > rhs.rating
        }
    }

    /// Hasta 15 pines en el canvas.
    private var visibleVenues: [BarPassVenue] {
        Array(rankedVenues.prefix(Self.maxVisiblePins))
    }

    /// Los que NO entran al canvas — alimentan el chip "+N" del cluster, que
    /// se dibuja en su centroide.
    private var hiddenVenues: [BarPassVenue] {
        Array(rankedVenues.dropFirst(Self.maxVisiblePins))
    }

    private var hiddenPinCount: Int { hiddenVenues.count }

    /// Cuántos de los venues filtrados están abiertos ahora — chip verde del
    /// canvas. Es un conteo sobre el set filtrado, no sobre un radio GPS.
    private var openNowCount: Int {
        filteredVenues.filter(\.isOpenNow).count
    }

    /// Qué venue va en el callout de abajo: el pin tocado si sigue visible;
    /// si no, el primero (el "mejor" por el orden de arriba).
    private var calloutVenue: BarPassVenue? {
        if let id = selectedPinID,
           let hit = visibleVenues.first(where: { $0.id == id }) {
            return hit
        }
        return visibleVenues.first
    }

    /// Bounding box de la CIUDAD, no de la capa filtrada. Padding del 12%
    /// para que ningún pin se pegue al borde del canvas (y para que una
    /// ciudad con un solo venue — e.g. el preview — no reviente la
    /// división por 0).
    private var cityBbox: (latMin: Double, latMax: Double, lngMin: Double, lngMax: Double)? {
        let lats = cityVenues.map(\.latitude)
        let lngs = cityVenues.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        let latPad = max((maxLat - minLat) * 0.12, 0.002)
        let lngPad = max((maxLng - minLng) * 0.12, 0.002)
        return (minLat - latPad, maxLat + latPad, minLng - lngPad, maxLng + lngPad)
    }

    /// Proyección lat/lng → canvas 0..1 contra `cityBbox`. Lat ↑ = canvas ↑,
    /// por eso el eje Y va invertido. La misma función la usan pines,
    /// cluster, etiquetas de barrio y el punto "me", así todos coinciden.
    private func normalized(lat: Double, lng: Double) -> CGPoint? {
        guard let bbox = cityBbox else { return nil }
        let latSpan = max(bbox.latMax - bbox.latMin, 0.0001)
        let lngSpan = max(bbox.lngMax - bbox.lngMin, 0.0001)
        let nx = (lng - bbox.lngMin) / lngSpan
        let ny = 1.0 - (lat - bbox.latMin) / latSpan
        return CGPoint(x: nx, y: ny)
    }

    /// Centroide (en coordenadas de canvas) de un grupo de venues.
    private func centroid(of venues: [BarPassVenue]) -> CGPoint? {
        guard !venues.isEmpty else { return nil }
        let lat = venues.map(\.latitude).reduce(0, +) / Double(venues.count)
        let lng = venues.map(\.longitude).reduce(0, +) / Double(venues.count)
        return normalized(lat: lat, lng: lng)
    }

    private var mapPins: [ExploreV2MapPin] {
        visibleVenues.compactMap { venue -> ExploreV2MapPin? in
            guard let p = normalized(lat: venue.latitude, lng: venue.longitude) else { return nil }
            let kind: ExploreV2MapPin.Kind = {
                if venue.id == selectedPinID { return .big }
                if venue.isTrending { return .standard }
                return .cold
            }()
            // Inicial del nombre — en 15 pines sobre 300pt no entra el
            // nombre completo. La identidad real se lee en el callout de
            // abajo y en el sheet.
            let initial = venue.name.first.map { String($0).uppercased() } ?? "·"
            return ExploreV2MapPin(
                id: venue.id,
                name: initial,
                x: p.x,
                y: p.y,
                kind: kind,
                clusterCount: nil
            )
        }
    }

    /// El chip "+N" del cluster, en el centroide real de los venues que
    /// esconde — sólo si hay alguno. El disco muestra "+N"; la cápsula de
    /// abajo muestra "N VENUES".
    private var clusterPin: ExploreV2MapPin? {
        guard hiddenPinCount > 0, let p = centroid(of: hiddenVenues) else { return nil }
        return ExploreV2MapPin(
            id: "cluster-overflow",
            name: "\(hiddenPinCount) venues",
            x: p.x, y: p.y,
            kind: .cluster,
            clusterCount: hiddenPinCount
        )
    }

    private var allPinsForCanvas: [ExploreV2MapPin] {
        if let clusterPin { return [clusterPin] + mapPins }
        return mapPins
    }

    /// Etiquetas de barrio: los hasta 3 `neighborhood` más frecuentes de la
    /// ciudad (mínimo 2 venues cada uno), en el centroide de sus venues.
    /// Si ningún barrio llega a 2 venues, no se dibuja ninguna — nunca un
    /// nombre inventado.
    private var districtMarks: [ExploreV2DistrictMark] {
        var groups: [String: [BarPassVenue]] = [:]
        for v in cityVenues {
            let hood = v.neighborhood.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hood.isEmpty else { continue }
            groups[hood, default: []].append(v)
        }
        return groups
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(3)
            .compactMap { hood, venues in
                centroid(of: venues).map { ExploreV2DistrictMark(text: hood.uppercased(), x: $0.x, y: $0.y) }
            }
    }

    /// Punto "me": la coordenada real del usuario proyectada al bbox, sólo si
    /// cae dentro del canvas. Sin permiso o en otra ciudad → nil → no se dibuja.
    private var mePoint: CGPoint? {
        guard let c = location.coordinate,
              let p = normalized(lat: c.latitude, lng: c.longitude),
              (0.0...1.0).contains(p.x), (0.0...1.0).contains(p.y)
        else { return nil }
        return p
    }

    /// Lo que se escribe al lado del buscador: el conteo real del set
    /// filtrado (con "Todos" y sin búsqueda es la ciudad entera, "1.814").
    private var venueCountLabel: String {
        filteredVenues.count.formatted(.number)
    }

    /// El botón "scope" del canvas: vuelve al estado por defecto de la ciudad
    /// (sin capa, sin búsqueda, sin selección). El bbox ya es siempre el de
    /// la ciudad, así que esto es lo único que hay que "recentrar".
    private func resetToCityDefault() {
        tap()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedLayer = .all
            searchText = ""
            selectedPinID = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        // Ciudad real: si VenueStore nos dio una (VenueStore ya sincroniza
        // su `selectedCity` con SelectedCityStore), va en mayúscula —
        // "MIAMI", "ATLANTA" — en el eyebrow y en el gran título. Si no
        // (primer launch antes del city picker), el eyebrow queda
        // "EXPLORAR" solo y el gran título oculta la palabra italic
        // (nada de "la ciudad" como literal — es una fabricación).
        let city = venueStore.selectedCity?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCity = !(city ?? "").isEmpty
        let cityUpper = (city ?? "").uppercased()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ExploreV2LiveDot()
                Text(hasCity ? "EXPLORAR · \(cityUpper)" : "EXPLORAR")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Color.bpAmberBright)
            }

            HStack(alignment: .firstTextBaseline) {
                Group {
                    if hasCity, let city {
                        (
                            Text("Explora ")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            + Text(city)
                                .font(.system(size: 30, design: .serif).italic())
                                .foregroundStyle(Color.bpAmberBright)
                        )
                    } else {
                        Text("Explora")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 10)

                ExploreV2SegmentToggle(selection: $viewMode)
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.6))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Buscar venues…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            )
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .tint(Color.bpAmber)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel("Buscar venues")

            if !searchText.isEmpty {
                Button {
                    tap()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }

            Text(venueCountLabel)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.bpAmber.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Layer pills

    private var layerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExploreV2Layer.allCases) { layer in
                    ExploreV2PinChip(
                        label: layer.label,
                        isOn: selectedLayer == layer
                    ) {
                        tap()
                        selectedLayer = layer
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Friends strip

    /// Real friends-out-tonight feed. Three states, none fabricated:
    /// opt-in prompt when location sharing is off, the strip when at least
    /// one friend is checked in, nothing at all otherwise (the card has no
    /// header of its own, so hiding it leaves no gap).
    @ViewBuilder
    private var friendsStrip: some View {
        if tonight.needsSharingOptIn {
            friendsStripCard(
                avatars: [],
                headline: friendsHeadline(bold: "Comparte tu ubicación", rest: " para ver a tu gente afuera"),
                sub: nil
            )
        } else if !tonight.friends.isEmpty {
            let friends = tonight.friends
            friendsStripCard(
                avatars: friends.prefix(3).map {
                    ExploreV2Friend(
                        initial: String($0.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(),
                        tint: ExploreV2Friend.tint(forSeed: $0.userId)
                    )
                },
                headline: friendsHeadline(
                    bold: friendNames(friends),
                    rest: friends.count == 1 ? " está afuera" : " están afuera"
                ),
                sub: friendsNeighborhoodDigest(friends)
            )
        } else {
            // No friends, no opt-in prompt: explicitly return nothing. The
            // parent VStack's spacing collapses around EmptyView, so the
            // strip leaves no gap when hidden. Being explicit here keeps
            // the @ViewBuilder honest for the compiler and the reader.
            EmptyView()
        }
    }

    private func friendsStripCard(avatars: [ExploreV2Friend], headline: Text, sub: String?) -> some View {
        Button {
            tap()
            // Tab 2 is Social — the full feed lives there.
            appState.switchTabPoppingToRoot(2)
        } label: {
            HStack(spacing: 12) {
                if !avatars.isEmpty {
                    HStack(spacing: -10) {
                        ForEach(avatars) { friend in
                            ExploreV2AvatarBadge(friend: friend)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    headline
                    if let sub {
                        Text(sub)
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 0)

                Text("›")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre la tab Social")
    }

    private func friendsHeadline(bold: String, rest: String) -> Text {
        let b: Text = Text(bold)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
        let r: Text = Text(rest)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(Color.white.opacity(0.72))
        return b + r
    }

    /// "Mía" · "Mía y Jules" · "Mía, Jules y Dani" · "Mía, Jules y 4 más".
    private func friendNames(_ friends: [FriendPresence]) -> String {
        let first = friends.map { f -> String in
            let n = f.name.trimmingCharacters(in: .whitespaces)
            return n.split(separator: " ").first.map(String.init) ?? n
        }
        switch first.count {
        case 0: return ""
        case 1: return first[0]
        case 2: return "\(first[0]) y \(first[1])"
        case 3: return "\(first[0]), \(first[1]) y \(first[2])"
        default: return "\(first[0]), \(first[1]) y \(first.count - 2) más"
        }
    }

    /// "2 EN WYNWOOD · 1 EN BRICKELL" from real check-ins, resolving each
    /// friend's venue to its neighborhood via the venue catalogue. Venues
    /// without a neighborhood are counted but not labelled; if none resolve,
    /// fall back to the plain count rather than inventing a district.
    private func friendsNeighborhoodDigest(_ friends: [FriendPresence]) -> String {
        var counts: [String: Int] = [:]
        for f in friends {
            if let hood = venueStore.venues.first(where: { $0.id == f.venueId })?.neighborhood,
               !hood.isEmpty {
                counts[hood, default: 0] += 1
            }
        }
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if ranked.isEmpty {
            return friends.count == 1 ? "1 AFUERA AHORA" : "\(friends.count) AFUERA AHORA"
        }
        return ranked.prefix(3)
            .map { "\($0.value) EN \($0.key.uppercased())" }
            .joined(separator: " · ")
    }

    // MARK: - Map

    private var mapCanvas: some View {
        ExploreV2MapCanvas(
            pins: allPinsForCanvas,
            districts: districtMarks,
            openNowCount: openNowCount,
            mePoint: mePoint,
            selectedID: $selectedPinID,
            onSelectPin: { pinID in
                // El cluster "+N" no abre venue (no es un venue solo); los
                // demás ids son UUID del catálogo real.
                guard pinID != "cluster-overflow",
                      let venue = visibleVenues.first(where: { $0.id == pinID })
                else { return }
                selectedVenue = venue
            },
            onRecenter: { resetToCityDefault() }
        )
        .frame(height: 300)
        .overlay {
            // Honest first-frame: cuando no hay venues cargados, cubrimos
            // la grilla stylized para que no se lea como "ciudad vacía".
            switch storeState {
            case .loading:
                mapLoadingOverlay
            case .error(let message):
                mapErrorOverlay(message: message)
            case .ready:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var mapLoadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.bpAmber)
            Text("CARGANDO VENUES…")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color.bpAmberBright.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando venues")
    }

    private func mapErrorOverlay(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.bpAmber)
            Text("NO PUDIMOS CARGAR VENUES")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.white.opacity(0.75))
            Button {
                tap()
                Task { await venueStore.loadVenues() }
            } label: {
                Text("Reintentar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.bpAmber))
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45))
    }

    // MARK: - Callout

    @ViewBuilder
    private var tappedCallout: some View {
        if let venue = calloutVenue {
            calloutRow(for: venue)
        } else {
            calloutPlaceholder
        }
    }

    /// Decide qué va en el callout cuando NO hay venue para mostrar. Antes
    /// esto siempre contestaba "Sin venues para esta capa"; ahora distingue
    /// loading / error / filtro vacío. Mantiene el mismo frame (16pt radius,
    /// black.opacity(0.55)) para que la pantalla no "salte" al cambiar de
    /// estado.
    @ViewBuilder
    private var calloutPlaceholder: some View {
        switch storeState {
        case .loading:
            calloutLoading
        case .error(let message):
            calloutError(message: message)
        case .ready:
            calloutEmpty
        }
    }

    private var calloutLoading: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.bpAmber)
            Text("Cargando venues…")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando venues")
    }

    private func calloutError(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.bpAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("No pudimos cargar venues")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Toca reintentar")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                tap()
                Task { await venueStore.loadVenues() }
            } label: {
                Text("Reintentar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bpAmber))
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint(message)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Pieza de la línea meta del callout: texto + color (nil = gris base).
    private struct CalloutMeta: Identifiable {
        let id: Int
        let text: String
        let color: Color?
    }

    /// Sólo lo que el venue realmente tiene: rating si > 0, precio si está
    /// cargado, "Abierto" / "Trending" si aplica. Sin rating no hay "★ 0.0"
    /// ni separador colgando.
    private func calloutMeta(for venue: BarPassVenue) -> [CalloutMeta] {
        var out: [(String, Color?)] = []
        if venue.rating > 0 {
            out.append(("★ " + String(format: "%.1f", venue.rating), nil))
        }
        if let priceSymbol = venue.priceTier.symbol {
            out.append((priceSymbol, nil))
        }
        if venue.isOpenNow {
            out.append(("Abierto", Color.bpGreen))
        }
        if venue.isTrending {
            out.append(("🔥 Trending", Color.bpAmberBright))
        }
        return out.enumerated().map { CalloutMeta(id: $0.offset, text: $0.element.0, color: $0.element.1) }
    }

    /// "Barrio · Tipo" — o sólo el tipo si el barrio está vacío. Nunca un
    /// separador delante de nada.
    private func calloutSubtitle(for venue: BarPassVenue) -> String {
        [venue.neighborhood.trimmingCharacters(in: .whitespacesAndNewlines), venue.type.displayName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func calloutRow(for venue: BarPassVenue) -> some View {
        let initial = venue.name.first.map { String($0).uppercased() } ?? "·"
        let meta = calloutMeta(for: venue)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.21, blue: 0.74),
                                Color(red: 0.18, green: 0.06, blue: 0.32)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                Text(initial)
                    .font(.system(size: 22, design: .serif).italic())
                    .foregroundStyle(.white)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(calloutSubtitle(for: venue))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                if !meta.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(meta) { item in
                            if item.id > 0 {
                                Text("·")
                            }
                            Text(item.text)
                                .foregroundStyle(item.color ?? Color.white.opacity(0.65))
                        }
                    }
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                tap()
                selectedVenue = venue
            } label: {
                Text("Ver venue")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bpAmber))
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tap()
            selectedVenue = venue
        }
    }

    /// La capa activa (o la búsqueda) no devolvió venues — p. ej. "Rooftops"
    /// en una ciudad sin rooftops, o la primera carga antes de que
    /// `venueStore` responda. Mantiene el frame del callout para que la
    /// pantalla no "salte".
    private var calloutEmpty: some View {
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 12) {
            Text(searching ? "Sin venues para esta búsqueda" : "Sin venues para esta capa")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer(minLength: 0)
            Text(searching ? "Prueba otra búsqueda" : "Toca otra capa")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.bpAmber.opacity(0.75))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - List mode

    /// Modo "Lista": las mismas filas del callout, una por venue filtrado,
    /// en el mismo orden que el canvas (trending primero, después rating).
    /// Tap en la fila o en "Ver venue" abre el sheet igual que un pin.
    @ViewBuilder
    private var venueList: some View {
        if rankedVenues.isEmpty {
            // Mismo dispatcher que el callout del mapa — loading / error /
            // filtro vacío, no un literal "Sin venues" ciego.
            calloutPlaceholder
        } else {
            LazyVStack(spacing: 10) {
                ForEach(rankedVenues) { venue in
                    calloutRow(for: venue)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Enums / models

private enum ExploreV2ViewMode: String, CaseIterable, Identifiable {
    case map, list
    var id: String { rawValue }
    var label: String { self == .map ? "Mapa" : "Lista" }
}

private enum ExploreV2Layer: String, CaseIterable, Identifiable {
    case all, trending, happyHour, rooftops, liveMusic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "Todos"
        case .trending:  return "🔥 Trending"
        case .happyHour: return "🍹 Happy Hour"
        case .rooftops:  return "🌆 Rooftops"
        case .liveMusic: return "🎸 Música en vivo"
        }
    }
}

private struct ExploreV2Friend: Identifiable {
    let id = UUID()
    let initial: String
    let tint: Color

    /// Stable, legible avatar color from a user id — same palette the Trips
    /// avatar stack uses, so one friend keeps one color across screens.
    static func tint(forSeed seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.92, green: 0.72, blue: 0.28),
            Color(red: 0.55, green: 0.40, blue: 0.95),
            Color(red: 0.20, green: 0.90, blue: 0.40),
            Color(red: 0.93, green: 0.93, blue: 0.95),
            Color(red: 0.11, green: 0.11, blue: 0.13),
            Color(red: 0.91, green: 0.28, blue: 0.37),
            Color(red: 0.18, green: 0.33, blue: 0.79),
        ]
        var hash = 0
        for scalar in seed.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        return palette[abs(hash) % palette.count]
    }

    #if DEBUG
    static let sample: [ExploreV2Friend] = [
        .init(initial: "M", tint: Color(red: 0.55, green: 0.40, blue: 0.95)),
        .init(initial: "J", tint: Color(red: 0.20, green: 0.90, blue: 0.40)),
        .init(initial: "D", tint: Color(red: 0.92, green: 0.92, blue: 0.95)),
    ]
    #endif
}

private struct ExploreV2MapPin: Identifiable {
    enum Kind { case cluster, cold, standard, big }
    let id: String
    let name: String
    let x: CGFloat // 0..1
    let y: CGFloat // 0..1
    let kind: Kind
    /// Sólo para `.cluster` — el número que se dibuja dentro del disco.
    /// Antes era "12" literal; ahora cada cluster trae su conteo real.
    let clusterCount: Int?

    #if DEBUG
    /// Fixtures del artifact v17.1 — se mantienen para que la vista
    /// `#Preview` y el menú de debug sigan dibujando el mockup estático
    /// cuando el store todavía no cargó la ciudad.
    static let sample: [ExploreV2MapPin] = [
        .init(id: "cluster", name: "12 venues", x: 0.30, y: 0.26, kind: .cluster, clusterCount: 12),
        .init(id: "floyd",   name: "Floyd",     x: 0.64, y: 0.27, kind: .cold, clusterCount: nil),
        .init(id: "e11even", name: "E11EVEN",   x: 0.69, y: 0.37, kind: .standard, clusterCount: nil),
        .init(id: "space",   name: "CLUB SPACE", x: 0.62, y: 0.46, kind: .big, clusterCount: nil),
        .init(id: "blackbird", name: "Blackbird Ordinary", x: 0.40, y: 0.68, kind: .standard, clusterCount: nil),
        .init(id: "sugar",   name: "Sugar Rooftop", x: 0.34, y: 0.78, kind: .standard, clusterCount: nil),
    ]
    #endif
}

/// Etiqueta de barrio sobre el canvas, en coordenadas 0..1 (mismo bbox que
/// los pines). Derivada de los `neighborhood` reales de la ciudad.
private struct ExploreV2DistrictMark: Identifiable {
    var id: String { text }
    let text: String
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Live dot

@MainActor
private struct ExploreV2LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.bpAmberBright)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .fill(Color.bpAmberBright)
                    .blur(radius: 4)
                    .opacity(pulse ? 0.3 : 0.75)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Segmented toggle (Mapa / Lista)

@MainActor
private struct ExploreV2SegmentToggle: View {
    @Binding var selection: ExploreV2ViewMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ExploreV2ViewMode.allCases) { mode in
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    selection = mode
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(selection == mode ? .black : Color.white.opacity(0.7))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == mode ? Color.bpAmber : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Pill chip (layer filters)

@MainActor
private struct ExploreV2PinChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(isOn ? .black : Color.white.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn ? Color.bpAmber : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.bpAmberBright : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friends avatar

@MainActor
private struct ExploreV2AvatarBadge: View {
    let friend: ExploreV2Friend

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [friend.tint, friend.tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(friend.initial)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.72))
        }
        .frame(width: 30, height: 30)
        .overlay(
            Circle().strokeBorder(Color(red: 0.03, green: 0.02, blue: 0.06), lineWidth: 2)
        )
    }
}

// MARK: - Map canvas

@MainActor
private struct ExploreV2MapCanvas: View {
    let pins: [ExploreV2MapPin]
    /// Etiquetas de barrio reales (hasta 3). Vacío → no se dibuja ninguna.
    var districts: [ExploreV2DistrictMark] = []
    /// Venues abiertos ahora en el set filtrado. 0 → el chip no se dibuja.
    var openNowCount: Int = 0
    /// Ubicación del usuario proyectada al canvas. nil → sin punto "me".
    var mePoint: CGPoint? = nil
    @Binding var selectedID: String?
    /// Qué hacer cuando el usuario toca un pin — además de marcarlo como
    /// seleccionado. Para pines de venue real, abre el sheet. Para el
    /// cluster "+N", el padre lo ignora.
    var onSelectPin: ((String) -> Void)? = nil
    /// Botón "scope": el padre resetea capa / búsqueda / selección.
    var onRecenter: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base deep navy
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.05, blue: 0.11),
                        Color(red: 0.09, green: 0.03, blue: 0.14)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                // Stylized "water" wash — bottom-left wedge, cooler blue
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.55))
                    p.addQuadCurve(
                        to: CGPoint(x: geo.size.width * 0.42, y: geo.size.height),
                        control: CGPoint(x: geo.size.width * 0.08, y: geo.size.height * 0.95)
                    )
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.14, blue: 0.26).opacity(0.9),
                            Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.95)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // Grid of streets as faint lines
                ExploreV2StreetGrid()
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.6)

                // Diagonal highway accent
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width * 0.1, y: geo.size.height * 0.9))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.9, y: geo.size.height * 0.15))
                }
                .stroke(Color.bpAmber.opacity(0.08), lineWidth: 1.5)

                // Neighborhood labels — real `neighborhood` values, at the
                // centroid of their venues (same bbox as the pins).
                ForEach(districts) { mark in
                    ExploreV2DistrictLabel(
                        mark.text,
                        at: CGPoint(x: geo.size.width * mark.x, y: geo.size.height * mark.y)
                    )
                }

                // Overlay chips (top-left anchored so a longer count never
                // pushes the capsule off the edge; hidden when nothing is open)
                if openNowCount > 0 {
                    ExploreV2OverlayChip(openNowCount: openNowCount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                }

                Button {
                    onRecenter?()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restablecer mapa")
                .position(x: geo.size.width - 28, y: 24)

                // "Me" dot — only when a real fix exists and lands in this city
                if let mePoint {
                    ExploreV2MeDot()
                        .position(
                            x: geo.size.width * mePoint.x,
                            y: geo.size.height * mePoint.y
                        )
                }

                // Pins
                ForEach(pins) { pin in
                    ExploreV2PinView(pin: pin, isSelected: selectedID == pin.id)
                        .position(
                            x: geo.size.width * pin.x,
                            y: geo.size.height * pin.y
                        )
                        .onTapGesture {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedID = pin.id
                            onSelectPin?(pin.id)
                        }
                }
            }
        }
    }
}

// MARK: - Street grid shape

private struct ExploreV2StreetGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let hStep: CGFloat = 36
        let vStep: CGFloat = 40
        var y: CGFloat = 0
        while y < rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += hStep
        }
        var x: CGFloat = 0
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += vStep
        }
        return p
    }
}

// MARK: - District label

@MainActor
private struct ExploreV2DistrictLabel: View {
    let text: String
    let point: CGPoint
    init(_ text: String, at point: CGPoint) {
        self.text = text
        self.point = point
    }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(2.4)
            .foregroundStyle(Color.white.opacity(0.22))
            .position(point)
    }
}

// MARK: - Overlay chip (N abiertos ahora)

@MainActor
private struct ExploreV2OverlayChip: View {
    /// Conteo real de `isOpenNow` en el set filtrado. El padre no dibuja el
    /// chip cuando es 0.
    let openNowCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.bpGreen)
                .frame(width: 6, height: 6)
                .overlay(Circle().fill(Color.bpGreen).blur(radius: 3).opacity(0.6))
            Text(openNowCount == 1 ? "1 abierto ahora" : "\(openNowCount) abiertos ahora")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - "Me" dot

@MainActor
private struct ExploreV2MeDot: View {
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.bpAmber.opacity(0.5), lineWidth: 2)
                .frame(width: 32, height: 32)
                .scaleEffect(ping ? 1.6 : 1.0)
                .opacity(ping ? 0 : 0.9)
            Circle()
                .fill(Color.bpAmber)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ping = true
            }
        }
    }
}

// MARK: - Pin view

@MainActor
private struct ExploreV2PinView: View {
    let pin: ExploreV2MapPin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            dot
            label
        }
    }

    @ViewBuilder
    private var dot: some View {
        switch pin.kind {
        case .cluster:
            // Antes "12" fijo. Ahora: si el pin trae `clusterCount` lo
            // usamos (+N venues ocultos); si no — caso del fixture viejo —
            // caemos a lo que diga `pin.name` (preserva el preview).
            ZStack {
                Circle()
                    .fill(Color.bpAmber.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.bpAmberBright, lineWidth: 1.5))
                Text(pin.clusterCount.map { "+\($0)" } ?? pin.name)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .cold:
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        case .standard:
            ZStack {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 22, height: 22)
                    .opacity(0.25)
                    .blur(radius: 2)
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 14, height: 14)
            }
        case .big:
            ZStack {
                Circle()
                    .fill(Color.bpAmberBright)
                    .frame(width: 32, height: 32)
                    .opacity(0.35)
                    .blur(radius: 3)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.bpAmberBright, Color.bpAmber],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSelected)
        }
    }

    @ViewBuilder
    private var label: some View {
        let isCold = pin.kind == .cold
        let isBig = pin.kind == .big
        Text(pin.name.uppercased())
            .font(.system(size: isBig ? 10.5 : 9.5, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(
                isCold ? Color.white.opacity(0.5) :
                (isBig ? .white : Color.white.opacity(0.9))
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(Color.black.opacity(isCold ? 0.35 : 0.6))
            )
            .overlay(
                Capsule().strokeBorder(
                    isBig ? Color.bpAmber.opacity(0.6) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
            )
    }
}

// MARK: - Background (Miami eye + warm vignette + grain)

@MainActor
private struct ExploreV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3,
                           height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.08)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.22),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    ExploreV2View()
        .environmentObject(VenueStore(repository: LocalVenueRepository()))
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
