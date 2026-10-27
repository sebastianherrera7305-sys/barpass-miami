import SwiftUI
import MapKit

/// Fallback de la cámara de MapKit sobre Miami, con los números que escribió
/// el owner en CLAUDE.md (lat 25.78, lng -80.19, span 0.12/0.12). Vive al
/// nivel del módulo para poder inicializar el `@State` de `ExploreV2View`
/// sin referenciar `self` en la expresión por defecto.
private let exploreV2MiamiFallbackRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.19),
    span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
)

// ExploreV2View — Pantalla "Explore" del artifact v17.1 (sección "Tabs",
// líneas 611-740 del HTML). Mapa real (MapKit) de la ciudad con pines en
// vivo, búsqueda, capas (Trending / Happy Hour / Rooftops / Música en vivo)
// y la tarjeta del venue tocado.
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
//   ciudad; el chip "N abiertos ahora" cuenta `isOpenNow` del set filtrado;
//   el cluster "+N" se ubica en el centroide real de los venues que esconde.
//
// Tercer pase (2026-10-12 · Build 92 → 93): el mapa pasó a MapKit real.
// - Comentario del owner en Build 92: "The map its really bad no se ve
//   nada bien". El canvas estilizado (grid + wedge + pines absolutos)
//   quedó reemplazado por `Map(position:) { ... }` (iOS 17 API) con
//   `Annotation` por cada venue, cluster real "+N" en el centroide de los
//   que no caben, texto plano por barrio y `UserAnnotation()` para el
//   usuario (si Core Location dio permiso).
// - Las coordenadas vienen directas de `BarPassVenue.latitude/longitude`.
//   La cámara arranca sobre Miami (25.78, -80.19, span 0.12/0.12) y se
//   re-ancla al bbox real de la ciudad cuando VenueStore entrega venues
//   o cuando `selectedCity` cambia. El botón "scope" vuelve a ese bbox
//   (ya con pan/zoom real que recentrar) y resetea filtros + búsqueda.
// - Topamos los pines a 15 (igual que antes) para que la vista no se
//   satura; el resto se agrupa en un único "+N" en su centroide real,
//   bajo el cap de 50 que MapKit tolera cómodo con `Annotation`.

@MainActor
struct ExploreV2View: View {
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared
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

    /// Cámara de MapKit. Arranca sobre Miami (owner-approved en CLAUDE.md),
    /// se re-ancla al bbox real de la ciudad en cuanto el VenueStore
    /// entrega venues o cuando `selectedCity` cambia — y el botón "scope"
    /// hace lo mismo bajo demanda. Si el usuario paneó/zoomeó por su cuenta
    /// no lo sobrescribimos: `hasAnchoredCamera` nos deja anclar sólo una
    /// vez por ciudad.
    @State private var cameraPosition: MapCameraPosition = .region(exploreV2MiamiFallbackRegion)
    @State private var hasAnchoredCamera = false

    /// Más de 15 pines sobre un mapa de 300pt empieza a verse como ruido —
    /// y nos mantiene por debajo del cap informal (~50 anotaciones) donde
    /// MapKit anima sin dropear frames. El resto se agrupa en un único
    /// "+N" en su centroide real.
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
            // Primer frame: si VenueStore ya tenía venues antes de que
            // esta vista se montara, anclar la cámara ahora mismo (sin
            // esperar un onChange que nunca va a disparar).
            anchorCameraToCityIfNeeded()
        }
        // El VenueStore entregó venues (o entregó más): intentar anclar.
        // `anchorCameraToCityIfNeeded` ya es idempotente — sólo mueve la
        // cámara la primera vez por ciudad.
        .onChange(of: cityVenues.count) { _, _ in
            anchorCameraToCityIfNeeded()
        }
        // El usuario cambió de ciudad (city picker) — soltar el flag y
        // re-anclar al bbox nuevo.
        .onChange(of: venueStore.selectedCity ?? "") { _, _ in
            hasAnchoredCamera = false
            anchorCameraToCityIfNeeded()
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
        case .rooftops:  return cityVenues.filter { $0.effectiveType == .rooftop }
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

    /// Bounding box de la CIUDAD, no de la capa filtrada. Devuelve una
    /// `MKCoordinateRegion` con padding del 12% para que ningún pin quede
    /// pegado al borde del mapa, con un piso mínimo que previene regiones
    /// degeneradas (una ciudad con un solo venue — e.g. el preview).
    private var cityRegion: MKCoordinateRegion? {
        let lats = cityVenues.map(\.latitude)
        let lngs = cityVenues.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        let latSpan = max((maxLat - minLat) * 1.24, 0.02)
        let lngSpan = max((maxLng - minLng) * 1.24, 0.02)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lngSpan)
        )
    }

    /// Centroide real (CLLocationCoordinate2D) de un grupo de venues — lo
    /// usan el cluster "+N" y las etiquetas de barrio.
    private func centroid(of venues: [BarPassVenue]) -> CLLocationCoordinate2D? {
        guard !venues.isEmpty else { return nil }
        let lat = venues.map(\.latitude).reduce(0, +) / Double(venues.count)
        let lng = venues.map(\.longitude).reduce(0, +) / Double(venues.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Lo que renderizamos como pin sobre el mapa real. El `kind` sigue la
    /// misma jerarquía visual que antes: el seleccionado se agranda, los
    /// trending resaltan en ámbar fuerte, el resto queda sutil.
    private var mapAnnotations: [ExploreV2MapPin] {
        visibleVenues.map { venue in
            let kind: ExploreV2MapPin.Kind = {
                if venue.id == selectedPinID { return .big }
                if venue.isTrending { return .standard }
                return .cold
            }()
            // Inicial del nombre — el nombre completo no entra en el disco.
            // La identidad real se lee en el callout de abajo y en el sheet.
            let initial = venue.name.first.map { String($0).uppercased() } ?? "·"
            return ExploreV2MapPin(
                id: venue.id,
                initial: initial,
                coordinate: CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude),
                kind: kind,
                clusterCount: nil
            )
        }
    }

    /// El chip "+N" del cluster, en el centroide real de los venues que
    /// esconde — sólo si hay alguno. El disco muestra "+N".
    private var clusterPin: ExploreV2MapPin? {
        guard hiddenPinCount > 0, let c = centroid(of: hiddenVenues) else { return nil }
        return ExploreV2MapPin(
            id: "cluster-overflow",
            initial: "+\(hiddenPinCount)",
            coordinate: c,
            kind: .cluster,
            clusterCount: hiddenPinCount
        )
    }

    /// Etiquetas de barrio: los hasta 3 `neighborhood` más frecuentes de la
    /// ciudad (mínimo 2 venues cada uno), en el centroide real de sus
    /// venues. Si ningún barrio llega a 2 venues, no se dibuja ninguna —
    /// nunca un nombre inventado.
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
                centroid(of: venues).map {
                    ExploreV2DistrictMark(text: hood.uppercased(), coordinate: $0)
                }
            }
    }

    /// Lo que se escribe al lado del buscador: el conteo real del set
    /// filtrado (con "Todos" y sin búsqueda es la ciudad entera, "1.814").
    private var venueCountLabel: String {
        filteredVenues.count.formatted(.number)
    }

    /// El botón "scope" del mapa: vuelve al estado por defecto de la ciudad
    /// — sin capa, sin búsqueda, sin selección, y re-ancla la cámara al
    /// bbox real (o al fallback de Miami si todavía no cargaron venues).
    private func resetToCityDefault() {
        tap()
        let target = cityRegion ?? exploreV2MiamiFallbackRegion
        withAnimation(.easeInOut(duration: 0.35)) {
            selectedLayer = .all
            searchText = ""
            selectedPinID = nil
            cameraPosition = .region(target)
        }
    }

    /// Ancla la cámara al bbox de la ciudad una sola vez por sesión-ciudad:
    /// cuando el VenueStore entrega venues por primera vez (o cuando el
    /// usuario cambia de ciudad y resetea el flag). Si el usuario ya paneó
    /// / zoomeó manualmente no lo pisamos — sólo el botón "scope" vuelve.
    private func anchorCameraToCityIfNeeded() {
        guard !hasAnchoredCamera, let region = cityRegion else { return }
        hasAnchoredCamera = true
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(region)
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
                            Text(l10n.t("exploreV2.header.prefix"))
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            + Text(city)
                                .font(.system(size: 30, design: .serif).italic())
                                .foregroundStyle(Color.bpAmberBright)
                        )
                    } else {
                        Text(l10n.t("exploreV2.header"))
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
        // Comment (Build 83): "este buscador no sirve y tampoco se ve bien,
        // se pierde en la transparencia". El campo vive sobre `CityArtMiami`
        // + viñeta cálida; con los valores que probé antes (fill 0.14 / stroke
        // 0.18 / ícono 0.85) seguía fundiéndose contra zonas amarillas del
        // arte. Esta pasada sube la base negra a 0.55, el fill blanco a 0.18,
        // el stroke a 0.22, y el ícono/clear se van a `bpAmberBright` para
        // que lean como una chip con identidad. Placeholder 0.75 (ya estaba
        // bien), texto siempre `.white`. El filtrado ya está cableado
        // (filteredVenues).
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.bpAmberBright)

            TextField(
                "",
                text: $searchText,
                prompt: Text(l10n.t("exploreV2.search.placeholder"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
            )
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .tint(Color.bpAmber)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel(l10n.t("common.searchVenues"))

            if !searchText.isEmpty {
                Button {
                    tap()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.bpAmberBright)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.t("exploreV2.clearSearch"))
            }

            Text(venueCountLabel)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.bpAmberBright)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.18))
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
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
        ZStack(alignment: .topLeading) {
            // El mapa real. `MapCameraPosition` queda en el binding —
            // paneos/zoom del usuario quedan registrados, y el botón
            // "scope" (abajo) lo vuelve a anclar al bbox de la ciudad.
            Map(position: $cameraPosition, interactionModes: .all) {
                // Un `Annotation` por venue visible. El tap abre el sheet
                // y además marca ese pin como seleccionado (lo agranda).
                ForEach(mapAnnotations) { pin in
                    Annotation("", coordinate: pin.coordinate, anchor: .center) {
                        ExploreV2VenueDot(
                            initial: pin.initial,
                            kind: pin.kind,
                            isSelected: selectedPinID == pin.id
                        )
                        .onTapGesture {
                            tap()
                            selectedPinID = pin.id
                            // El cluster "+N" nunca entra en `mapAnnotations`
                            // (se dibuja aparte), así que acá siempre hay
                            // venue real detrás del id.
                            if let venue = visibleVenues.first(where: { $0.id == pin.id }) {
                                selectedVenue = venue
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(pin.initial)
                        .accessibilityAddTraits(.isButton)
                    }
                }

                // Cluster "+N" en el centroide real de los venues que no
                // caben en el cap. No abre venue — es sólo señal visual
                // de "hay más acá".
                if let cluster = clusterPin {
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        ExploreV2ClusterDot(count: cluster.clusterCount ?? 0)
                            .accessibilityLabel("\(cluster.clusterCount ?? 0) venues más en esta zona")
                    }
                }

                // Etiquetas de barrio reales — texto plano, no interactúan.
                ForEach(districtMarks) { mark in
                    Annotation(mark.text, coordinate: mark.coordinate, anchor: .center) {
                        ExploreV2DistrictText(mark.text)
                    }
                }

                // Punto azul del usuario — se dibuja sólo si Core Location
                // ya entregó permiso + fix. Sin permiso MapKit lo esconde
                // en silencio, no necesitamos filtrarlo acá.
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))

            // Chip "N abiertos ahora" — mismo contador que antes, ahora
            // flotando sobre el mapa real.
            if openNowCount > 0 {
                ExploreV2OverlayChip(openNowCount: openNowCount)
                    .padding(12)
            }

            // Botón "scope": re-ancla al bbox de la ciudad y resetea los
            // filtros. Pegado a la esquina superior derecha.
            HStack {
                Spacer()
                Button {
                    resetToCityDefault()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.t("exploreV2.resetMap"))
            }
            .padding(12)
        }
        .frame(height: 300)
        .overlay {
            // Honest first-frame: cuando no hay venues cargados cubrimos
            // el mapa para que no se lea como "ciudad vacía". El overlay
            // va ANTES del clipShape para que el fondo del overlay quede
            // recortado al mismo radio que el mapa.
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
            Text(l10n.t("exploreV2.loading.caps"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color.bpAmberBright.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t("exploreV2.loadingA11y"))
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
                Text(l10n.t("common.retry"))
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
            Text(l10n.t("exploreV2.loading"))
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
        .accessibilityLabel(l10n.t("exploreV2.loadingA11y"))
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
                Text(l10n.t("exploreV2.tapRetry"))
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
                Text(l10n.t("common.retry"))
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
                Text(l10n.t("exploreV2.viewVenue"))
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

/// Pin que se dibuja sobre MapKit. `coordinate` es la posición real del
/// venue (o el centroide real del cluster "+N"); los paneos/zoom del mapa
/// re-proyectan por nosotros.
private struct ExploreV2MapPin: Identifiable {
    enum Kind { case cluster, cold, standard, big }
    let id: String
    /// Inicial del nombre para los pines de venue; "+N" para el cluster.
    let initial: String
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
    /// Sólo para `.cluster` — el número que se dibuja dentro del disco.
    /// Antes era "12" literal; ahora cada cluster trae su conteo real.
    let clusterCount: Int?
}

/// Etiqueta de barrio sobre el mapa — texto plano, en el centroide real
/// de los venues de ese `neighborhood`. Derivada de los `neighborhood`
/// reales de la ciudad; nunca un nombre inventado.
private struct ExploreV2DistrictMark: Identifiable {
    var id: String { text }
    let text: String
    let coordinate: CLLocationCoordinate2D
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

// MARK: - District label (texto plano sobre el mapa)

@MainActor
private struct ExploreV2DistrictText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(2.4)
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.black.opacity(0.45))
            )
            .accessibilityLabel(String(format: L10n.shared.t("exploreV2.neighborhoodA11yFmt"), text))
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

// MARK: - Venue dot (annotation body)

/// Dot que se dibuja sobre cada venue en MapKit: disco ámbar + inicial del
/// nombre, con tres variantes de énfasis (`cold` sutil / `standard` normal
/// / `big` cuando está seleccionado). Sin label flotante — la identidad
/// completa del venue se lee en el callout de abajo y en el sheet.
@MainActor
private struct ExploreV2VenueDot: View {
    let initial: String
    let kind: ExploreV2MapPin.Kind
    let isSelected: Bool

    var body: some View {
        switch kind {
        case .big:
            ZStack {
                Circle()
                    .fill(Color.bpAmberBright)
                    .frame(width: 36, height: 36)
                    .opacity(0.4)
                    .blur(radius: 4)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.bpAmberBright, Color.bpAmber],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 2))
                Text(initial)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSelected)
        case .standard:
            ZStack {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 26, height: 26)
                    .opacity(0.3)
                    .blur(radius: 2)
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.bpAmberBright.opacity(0.9), lineWidth: 1))
                Text(initial)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
        case .cold:
            ZStack {
                Circle()
                    .fill(Color.bpAmber.opacity(0.75))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                Text(initial)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
        case .cluster:
            // Un `.cluster` kind no debería llegar acá — el cluster "+N" se
            // dibuja con `ExploreV2ClusterDot`. Si llega, degradamos a algo
            // reconocible en lugar de colapsar.
            ExploreV2ClusterDot(count: Int(initial.dropFirst()) ?? 0)
        }
    }
}

// MARK: - Cluster dot (annotation body)

/// "+N" cluster que sustituye a los venues que no entran al cap. Sólo
/// aparece cuando `hiddenPinCount > 0` y queda sobre el centroide real
/// de los venues ocultos. No es tocable: es señal visual, no acceso.
@MainActor
private struct ExploreV2ClusterDot: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.bpAmber.opacity(0.95))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.bpAmberBright, lineWidth: 1.5))
            Text("+\(count)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
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
