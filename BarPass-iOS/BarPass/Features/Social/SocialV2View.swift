import SwiftUI

// SocialV2View — Tab Social v17.1 convergida en el artifact fc6e12c7 (owner,
// 2026-10-09). Es la nueva tab Social: historias por venue, feed de "tu gente"
// (eventos organizados, llegadas, salas de historias) y una tarjeta de evento
// que arma un amigo (co-planning).
//
// Vive al lado del SocialView actual sin reemplazarlo; se cablea desde
// MainTabView detrás de V2Flags.socialV2 (default OFF).
//
// Diseño en línea con OnboardingV2Flow y RemyLiveView: fondo compartido
// (CityArtMiami + vignette + grain), 70pt de spacer bajo la status bar,
// mezcla sans (SF Pro Display 900 rounded) + accent serif italic (bpAmberBright),
// eyebrows monospaced con tracking, tarjetas sobre blanco al 4%.
//
// Datos (cableados 2026-10-10, V1 pattern):
//   · nowFeed      ← FriendsTonightStore.shared.friends (RPC get_friends_out_tonight)
//   · storiesRail  ← VenueStoryPulseStore.shared.byVenue, cruzado contra venueStore
//                    (venue_story_pulse view, misma del rail de SocialView V1)
//   · hostCard     ← RepositoryDependencies.hostEvent.events(venueId: nil, limit: 20)
//                    filtrado a la ciudad del usuario (venueStore.venues),
//                    se muestra el primer evento no cancelado y futuro
//   · counters     ← conteo real de amigos en el feed; "en camino" no está
//                    en el modelo todavía (FriendPresence sólo tracks checkedInAt),
//                    por eso el segundo contador se omite hasta que exista.
//
// Limitaciones conservadas:
//   · Avatares siguen siendo placeholder de color + inicial. El avatar real
//     (FriendAvatar con AvatarConfig) existe pero el mockup pide un disco
//     con inicial sobre un gradient; mezclar los dos rompería la estética.
//     Cambio futuro si el owner lo pide.
//   · Pills: "Ahora" es el estado actual; "Eventos" → HostEventsListView,
//     "Amigos"/"Chats" → FriendsListView (mismo destino que SocialView V1).
//     "Historias" no se dibuja: no tiene pantalla propia y el rail ya está
//     abajo. Sin conteos inventados ("· 6") en ninguna.
//   · La tab bar inferior decorativa sólo existe en DEBUG para previews
//     standalone; en producción la pone MainTabView.

@MainActor
public struct SocialV2View: View {

    /// Cuando esta vista se usa dentro de `MainTabView`, la tab bar nativa
    /// de SwiftUI ya está debajo — no dibujamos la nuestra. En previews
    /// standalone se puede pasar `false` para ver el frame completo.
    private let embeddedInTabBar: Bool

    public init(embeddedInTabBar: Bool = true) {
        self.embeddedInTabBar = embeddedInTabBar
    }

    @EnvironmentObject private var venueStore: VenueStore
    @ObservedObject private var tonight = FriendsTonightStore.shared
    @ObservedObject private var pulse = VenueStoryPulseStore.shared

    @State private var events: [HostEvent] = []
    @State private var openStories: SocialV2StoryTarget?
    @State private var loadingStoriesFor: String?
    @State private var selectedVenue: BarPassVenue?
    @State private var selectedHostEvent: HostEvent?
    @State private var showFriends = false
    @State private var showHosting = false

    private let storyRepository: VenueStoryRepository = RepositoryDependencies.venueStory
    private let hostRepository = RepositoryDependencies.hostEvent

    public var body: some View {
        ZStack {
            SocialV2Background()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 70)

                    // Eyebrow — "Social · <ciudad> · HH:mm"
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.bpAmber)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .fill(Color.bpAmber.opacity(0.4))
                                    .frame(width: 12, height: 12)
                                    .blur(radius: 2)
                            )
                        Text(eyebrowText)
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(Color.bpAmber)
                    }
                    .padding(.horizontal, 24)

                    // Headline — "Tu gente está afuera"
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Tu gente")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1)
                            .foregroundStyle(.white)
                        Text("está afuera")
                            .font(.system(size: 32, design: .serif).italic())
                            .foregroundStyle(Color.bpAmberBright)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    // Sub-digest con contadores reales
                    subDigest
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                    // Pills — filtros del feed social
                    pillsRow
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    // "Ahora" — feed de tu gente en este momento
                    nowFeedSection
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    // Historias de esta noche — rail horizontal de venues
                    if !cityStories.isEmpty {
                        storiesSectionHeader
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                        storiesRail
                            .padding(.top, 12)
                    }

                    // Host card — próximo evento organizado por un host
                    if let event = nextHostEvent {
                        hostCard(for: event)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    }

                    // CTAs — "Levantar la mano" / "Armar algo"
                    bottomCTAs
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    Spacer().frame(height: embeddedInTabBar ? 40 : 100)
                }
            }

            // Tab bar decorativa — solo en previews standalone (DEBUG)
            #if DEBUG
            if !embeddedInTabBar {
                VStack {
                    Spacer()
                    SocialV2DecorativeTabBar()
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
        .task {
            BPAnalytics.track(.socialGraphViewed)
            await loadAll(force: false)
        }
        .refreshable { await loadAll(force: true) }
        .sheet(item: $selectedVenue) { venue in
            NavigationStack {
                VenueDetailView(venue: venue)
            }
            .presentationBackground(.black)
        }
        .sheet(item: $selectedHostEvent) { event in
            NavigationStack {
                HostEventDetailView(eventId: event.id)
            }
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showFriends) {
            NavigationStack { FriendsListView() }
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showHosting) {
            NavigationStack { HostEventsListView() }
                .presentationBackground(.black)
        }
        .fullScreenCover(item: $openStories) { target in
            StoryViewer(venueName: target.venueName, stories: target.stories) {
                openStories = nil
            }
        }
    }

    // MARK: - Data derivations

    /// Venues con historias en la noche en curso, cruzados contra el catálogo
    /// cargado para esta ciudad. `venueStore.venues` ya viene filtrado por
    /// `selectedCity`, así que una story cuyo venue no está en ese catálogo
    /// es de otra ciudad y se descarta (misma lógica que SocialView V1,
    /// TestFlight 2026-09-17).
    private var cityStories: [(venue: BarPassVenue, pulse: VenueStoryPulse)] {
        pulse.byVenue.values
            .sorted {
                if $0.posterCount != $1.posterCount { return $0.posterCount > $1.posterCount }
                return $0.latestAt > $1.latestAt
            }
            .compactMap { p in
                venueStore.venues.first(where: { $0.id == p.venueId }).map { ($0, p) }
            }
    }

    /// Evento más próximo (no cancelado, futuro) cuyo venue está en el
    /// catálogo de la ciudad del usuario.
    private var nextHostEvent: HostEvent? {
        let knownVenues = Set(venueStore.venues.map(\.id))
        let now = Date()
        return events
            .filter { !$0.isCancelled && knownVenues.contains($0.venue.id) && $0.startsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    /// "Social · <ciudad> · HH:mm". Sin ciudad seleccionada se omite ese
    /// segmento — nunca un fallback inventado.
    private var eyebrowText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: Date())
        if let city = venueStore.selectedCity, !city.isEmpty {
            return "Social · \(city) · \(time)"
        }
        return "Social · \(time)"
    }

    // MARK: - Sub-digest counters

    /// Contadores reales. "En camino" no existe en FriendPresence (todas las
    /// filas vienen de `get_friends_out_tonight()` que sólo registra check-in),
    /// así que mostramos sólo "N afuera" + el último arribo real si lo hay.
    private var subDigest: some View {
        let count = tonight.friends.count
        let latest = tonight.friends
            .max(by: { $0.checkedInAt < $1.checkedInAt })

        return Group {
            if tonight.needsSharingOptIn {
                Text("Comparte tu ubicación para ver a tu gente afuera.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
            } else if count == 0 {
                Text("Noche tranquila · nadie afuera por ahora")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
            } else if let latest {
                // "acaba de llegar" sólo si el check-in es realmente reciente;
                // las filas del RPC pueden tener horas (hasta ~30h).
                let isRecent = Date().timeIntervalSince(latest.checkedInAt) < 30 * 60
                digestWithArrival(count: count, name: latest.name, venue: latest.venueName, isRecent: isRecent)
            } else {
                digestCountOnly(count: count)
            }
        }
    }

    // Split into typed helpers: a 5-way `Text + Text` chain with per-segment
    // modifiers makes the Swift type-checker time out ("unable to type-check
    // this expression in reasonable time").
    private func digestWithArrival(count: Int, name: String, venue: String, isRecent: Bool) -> Text {
        let n: Text = Text("\(count)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(.white)
        let sep: Text = Text(" afuera · ")
            .font(.system(size: 13))
            .foregroundColor(Color.white.opacity(0.6))
        let who: Text = Text(name)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(.white)
        let verb: Text = Text(isRecent ? " acaba de llegar a " : " está en ")
            .font(.system(size: 13))
            .foregroundColor(Color.white.opacity(0.6))
        let place: Text = Text(venue)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(Color.bpAmberBright)
        return n + sep + who + verb + place
    }

    private func digestCountOnly(count: Int) -> Text {
        let n: Text = Text("\(count)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(.white)
        let tail: Text = Text(" afuera")
            .font(.system(size: 13))
            .foregroundColor(Color.white.opacity(0.6))
        return n + tail
    }

    // MARK: - Pills

    /// Cada pill abre un destino real (sin conteos inventados). "Amigos" y
    /// "Chats" van a `FriendsListView`, exactamente donde los manda SocialView
    /// V1 (los chats viven ahí; el reporte de TestFlight fue "no me aparecen
    /// mis chats"). "Eventos" abre `HostEventsListView`, el mismo destino que
    /// el CTA "Armar algo". La pill "Historias" del mockup no tiene pantalla
    /// propia, así que no se dibuja: el rail de historias ya está abajo.
    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                SocialV2Pill(text: "Ahora", isOn: true)
                SocialV2Pill(text: "Eventos") {
                    BPHaptics.light()
                    showHosting = true
                }
                SocialV2Pill(text: "Amigos") {
                    BPHaptics.light()
                    showFriends = true
                }
                SocialV2Pill(text: "Chats") {
                    BPHaptics.light()
                    showFriends = true
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Now feed

    @ViewBuilder
    private var nowFeedSection: some View {
        if tonight.isLoading && tonight.friends.isEmpty {
            SocialV2NowSkeleton()
        } else if tonight.needsSharingOptIn {
            SocialV2SharingOffCard { showFriends = true }
        } else if tonight.friends.isEmpty {
            SocialV2EmptyNowCard()
        } else {
            VStack(spacing: 0) {
                let rows = Array(tonight.friends.prefix(5))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, friend in
                    let venue = venueStore.venues.first(where: { $0.id == friend.venueId })
                    SocialV2NowRow(
                        avatar: SocialV2Avatar(
                            initial: initialFor(friend.name),
                            background: SocialV2Avatar.color(forSeed: friend.userId)
                        ),
                        name: "\(friend.name) · \(friend.venueName)",
                        detail: detailFor(friend),
                        chip: chipFor(friend, index: index),
                        onTap: {
                            BPHaptics.light()
                            if let venue { selectedVenue = venue }
                        }
                    )
                    if index < rows.count - 1 {
                        SocialV2Divider()
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
        }
    }

    private func initialFor(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "·" }
        return String(first).uppercased()
    }

    private func detailFor(_ f: FriendPresence) -> String {
        let seconds = Int(Date().timeIntervalSince(f.checkedInAt))
        let when: String
        if seconds < 60 { when = "llegó recién" }
        else if seconds < 3600 { when = "llegó hace \(seconds / 60) min" }
        else { when = "llegó hace \(seconds / 3600) h" }
        return when
    }

    /// El chip "hot" es decoración del mockup (el amber cantando "ve para
    /// allá"). Lo reservamos para el PRIMER amigo que llegó más reciente,
    /// como ancla visual, y el resto cae a ghost. Sin acción propia por
    /// ahora — el tap va a abrir el venue, no a lanzar un Uber.
    private func chipFor(_ f: FriendPresence, index: Int) -> SocialV2ChipSpec {
        if index == 0 {
            return SocialV2ChipSpec(text: "Ir", kind: .hot)
        }
        return SocialV2ChipSpec(text: "Ver", kind: .ghost)
    }

    // MARK: - Stories rail

    private var storiesSectionHeader: some View {
        HStack {
            Text("Historias de esta noche")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("\(cityStories.count) \(cityStories.count == 1 ? "venue" : "venues")")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.bpAmber)
        }
    }

    private var storiesRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cityStories, id: \.venue.id) { entry in
                    Button {
                        BPHaptics.light()
                        Task { await presentStories(at: entry.venue) }
                    } label: {
                        SocialV2StoryItem(
                            initial: initialFor(entry.venue.name),
                            label: entry.venue.name,
                            isBusy: entry.pulse.posterCount > 1,
                            isLoading: loadingStoriesFor == entry.venue.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollClipDisabled()
    }

    private func presentStories(at venue: BarPassVenue) async {
        loadingStoriesFor = venue.id
        defer { loadingStoriesFor = nil }
        let stories = (try? await storyRepository.stories(for: venue.id)) ?? []
        guard !stories.isEmpty else { return }
        openStories = SocialV2StoryTarget(venueName: venue.name, stories: stories)
    }

    // MARK: - Host card

    private func hostCard(for event: HostEvent) -> some View {
        let venue = venueStore.venues.first(where: { $0.id == event.venue.id })
        let placeName = event.venue.name ?? venue?.name ?? ""

        // Locale del dispositivo, sin DateFormatter por render.
        let eyebrow = event.startsAt
            .formatted(.dateTime.weekday(.wide).hour().minute())
            .capitalized
        let placeLine = placeName.isEmpty ? eyebrow : "\(eyebrow) · \(placeName)"

        return Button {
            BPHaptics.light()
            selectedHostEvent = event
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(placeLine)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.bpAmber)
                        .lineLimit(1)
                    Spacer()
                    Text("Ver detalle")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.bpAmber, in: Capsule())
                }

                Text(event.title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.bpAmber.opacity(0.14), Color.bpAmber.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpAmber.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom CTAs

    private var bottomCTAs: some View {
        HStack(spacing: 10) {
            Button {
                BPHaptics.light()
                showFriends = true
            } label: {
                HStack(spacing: 6) {
                    Text("\u{270B}")
                    Text("Levantar la mano")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Button {
                BPHaptics.light()
                showHosting = true
            } label: {
                HStack(spacing: 6) {
                    Text("+")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Text("Armar algo")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    /// Carga paralela, misma política que SocialView V1 (`load(force:)`).
    private func loadAll(force: Bool) async {
        pulse.refresh(force: force)
        async let friendsRefresh: Void = tonight.refresh(force: force)
        async let fetchedEvents = (try? await hostRepository.events(venueId: nil, limit: 20)) ?? []
        _ = await friendsRefresh
        let nights = await fetchedEvents
        events = nights.filter { !$0.isCancelled }
    }
}

// MARK: - Sheet identifiables

/// `fullScreenCover(item:)` necesita un payload Identifiable; mismo patrón que
/// SocialView V1 — llevamos el nombre + los frames ya cargados.
private struct SocialV2StoryTarget: Identifiable {
    let venueName: String
    let stories: [VenueStory]
    var id: String { stories.first?.id ?? venueName }
}

// MARK: - Background

@MainActor
private struct SocialV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3, height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * -0.1)
                    .opacity(0.55)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Pills

/// Pill del filtro social. La activa ("Ahora") es el estado actual y no es
/// tappable; las demás son botones reales con destino.
@MainActor
private struct SocialV2Pill: View {
    let text: String
    var isOn: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                isOn ? AnyShapeStyle(Color.bpAmber) : AnyShapeStyle(Color.white.opacity(0.07)),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? Color.bpAmberBright : Color.white.opacity(0.1),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
    }
}

// MARK: - Now feed row

private struct SocialV2ChipSpec {
    enum Kind { case hot, ghost }
    let text: String
    let kind: Kind
}

@MainActor
private struct SocialV2NowRow: View {
    let avatar: SocialV2Avatar
    let name: String
    let detail: String
    let chip: SocialV2ChipSpec
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 11) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                chipView
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipView: some View {
        Group {
            switch chip.kind {
            case .hot:
                Text(chip.text)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.bpAmber, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
                    .shadow(color: Color.bpAmber.opacity(0.5), radius: 6, y: 0)
            case .ghost:
                Text(chip.text)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.bpAmber.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
            }
        }
    }
}

@MainActor
private struct SocialV2Divider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }
}

// MARK: - Empty / sharing-off / skeleton

@MainActor
private struct SocialV2EmptyNowCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Noche tranquila")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Nadie de tu gente está afuera por ahora. Levanta la mano para avisarles.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.07)))
    }
}

@MainActor
private struct SocialV2SharingOffCard: View {
    let onOpenFriends: () -> Void

    var body: some View {
        Button(action: onOpenFriends) {
            HStack(spacing: 11) {
                Image(systemName: "location.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comparte tu ubicación para ver a tu gente")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text("Es recíproco · nadie te ve si tú no compartes")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct SocialV2NowSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 11) {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 11)
                            .frame(maxWidth: 180, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 9)
                            .frame(maxWidth: 140, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Avatars

@MainActor
private struct SocialV2Avatar: View {
    let initial: String
    let background: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [background, background.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(initial)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: 42, height: 42)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    /// Color legible y estable a partir de cualquier semilla (user id).
    static func color(forSeed seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.92, green: 0.72, blue: 0.28),
            Color(red: 0.55, green: 0.4,  blue: 0.95),
            Color(red: 0.2,  green: 0.9,  blue: 0.4),
            Color(red: 0.93, green: 0.93, blue: 0.95),
            Color(red: 0.11, green: 0.11, blue: 0.13),
            Color(red: 0.91, green: 0.28, blue: 0.37),
            Color(red: 0.18, green: 0.33, blue: 0.79),
        ]
        var hash = 0
        for scalar in seed.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        // `abs(Int.min)` trapea; `& Int.max` limpia el signo sin overflow.
        return palette[(hash & Int.max) % palette.count]
    }
}

// MARK: - Stories rail

/// `isBusy` = más de una persona posteando en ese venue esta noche
/// (`posterCount > 1`). Es ocupación, no novedad: el anillo amber marca
/// "hay movimiento", no "no lo viste".
@MainActor
private struct SocialV2StoryItem: View {
    let initial: String
    let label: String
    let isBusy: Bool
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.06, blue: 0.13))
                Text(initial)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if isLoading {
                    Circle().fill(Color.black.opacity(0.5))
                    ProgressView().tint(Color.bpAmber)
                }
            }
            .frame(width: 52, height: 52)
            .overlay(
                Circle().strokeBorder(
                    isBusy ? Color.bpAmber : Color.white.opacity(0.2),
                    lineWidth: isBusy ? 2 : 1.5
                )
            )
            .shadow(
                color: isBusy ? Color.bpAmber.opacity(0.5) : .clear,
                radius: isBusy ? 10 : 0
            )

            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Decorative tab bar (previews only)

#if DEBUG
@MainActor
private struct SocialV2DecorativeTabBar: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SocialV2TabItem.all.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 3) {
                    Image(systemName: t.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(t.label)
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(t.isOn ? Color.bpAmber : Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .background(
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct SocialV2TabItem {
    let label: String
    let icon: String
    let isOn: Bool

    static let all: [SocialV2TabItem] = [
        .init(label: "TONIGHT", icon: "flame.fill", isOn: false),
        .init(label: "EXPLORE", icon: "map", isOn: false),
        .init(label: "SOCIAL", icon: "person.2.fill", isOn: true),
        .init(label: "TRIPS", icon: "suitcase.fill", isOn: false),
        .init(label: "ME", icon: "person.crop.circle", isOn: false),
    ]
}
#endif

// MARK: - Preview

#if DEBUG
#Preview("Social v2 — standalone") {
    SocialV2View(embeddedInTabBar: false)
        .environmentObject(VenueStore())
}

#Preview("Social v2 — embedded") {
    SocialV2View()
        .environmentObject(VenueStore())
}
#endif
