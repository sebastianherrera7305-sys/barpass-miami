import SwiftUI

// TripsListV2View — pantalla "Trips" (lista) convergida en el artifact v17.1
// (mockup líneas 918-1256, "Pantallas v17.1 — Trips").
//
// Es la LISTA de trips del usuario, no el detalle. El detalle vive en
// GroupNightView. Esta pantalla muestra:
//   · header editorial "Tus trips" + eyebrow "Trips · N planes"
//   · dos CTAs: "Unirme con código" (ghost) y "Crear trip nuevo" (amber + flecha)
//   · 3 tarjetas de trip (Activo con punto live · Planeando · Completado)
//     cada una con título, status tag, sub (fecha · paradas · miembros),
//     ruta en mono con flechas italic, avatar stack y meta line a la derecha
//   · sección "Trips públicos para unirte" con 2 filas (ícono + nombre/sub + Unirme)
//
// Limitaciones (notadas en el schema):
//   · Los datos son literales del mockup, no vienen de TripStore todavía — el
//     wiring con VenueStore/TripRepository se hace en un pase siguiente.
//   · Los avatars del mockup son SVGs complejos (caras generativas); acá se
//     aproximan con círculos de color + inicial. El stack preserva el patrón
//     visual (5 overlap + "+N") pero no la cara.
//   · No incluye el tab bar inferior porque esta vista es contenido del tab;
//     el MainTabView provee la navegación.
//   · El status bar (23:41 · SOS · 63%) del mockup no se dibuja porque iOS
//     ya pinta el system status bar; mantenerlo duplicaría la hora.
//   · Las fuentes custom (Bebas Neue, Instrument Serif, Courier Prime) del
//     artifact se aproximan con .system(design: .rounded/.serif/.monospaced).

@MainActor
public struct TripsListV2View: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState: AppState

    @StateObject private var tripStore = TripStore(
        repository: RepositoryDependencies.trip
    )

    @State private var selectedTrip: Trip? = nil
    @State private var showCreateChoice = false
    @State private var showCreateFlow = false
    @State private var showManualCreate = false
    @State private var showJoinByCode = false
    @State private var joinCode = ""
    @State private var joinError: String? = nil
    @State private var isJoiningByCode = false

    public init() {}

    public var body: some View {
        ZStack {
            TripsListV2Background()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer().frame(height: 70)

                    TripsListV2Header(planCount: tripStore.myTrips.count)
                        .padding(.horizontal, 20)

                    TripsListV2ActionRow(
                        onJoin:  { showJoinByCode = true },
                        onCreate: { showCreateChoice = true }
                    )
                    .padding(.horizontal, 20)

                    if let error = tripStore.loadError {
                        TripsListV2ErrorView(message: error) {
                            Task { await tripStore.loadTrips() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    } else if tripStore.isLoading && tripStore.trips.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                ShimmerSkeleton(height: 118)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    } else {
                        if tripStore.myTrips.isEmpty {
                            TripsListV2EmptyMyTrips()
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                        } else {
                            VStack(spacing: 14) {
                                ForEach(tripStore.myTrips) { trip in
                                    TripsListV2Card(
                                        trip: trip.asV2CardModel,
                                        onTap: { selectedTrip = trip }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        }

                        if !tripStore.discoverableTrips.isEmpty {
                            TripsListV2PublicSection(
                                rows: tripStore.discoverableTrips.map { $0.asV2PublicRow },
                                onJoin: { row in
                                    guard let id = row.tripId,
                                          let trip = tripStore.discoverableTrips
                                                     .first(where: { $0.id == id })
                                    else { return }
                                    selectedTrip = trip
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                        }
                    }

                    Spacer().frame(height: 100)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await tripStore.loadTrips() }
        .onAppear { BPAnalytics.track(.viewScreen("Trips")) }
        .onReceive(appState.$pendingRoute.compactMap { $0 }) { route in
            guard case .trip(let id) = route else { return }
            Task {
                if tripStore.trips.isEmpty { await tripStore.loadTrips() }
                if let trip = tripStore.trips.first(where: { $0.id == id }) {
                    selectedTrip = trip
                }
                appState.consumeRoute()
            }
        }
        .confirmationDialog(
            l10n.t("trips.createChoice.title"),
            isPresented: $showCreateChoice,
            titleVisibility: .visible
        ) {
            Button(l10n.t("trips.createChoice.ai"))     { showCreateFlow   = true }
            Button(l10n.t("trips.createChoice.manual")) { showManualCreate = true }
            Button(l10n.t("tripCreate.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showCreateFlow) {
            PromptYourNightView(venues: venueStore.venues) { title, venues in
                createTripFromPrompt(title: title, venues: venues)
            }
            .presentationDetents([.large])
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showManualCreate) {
            TripCreateFlow(venues: venueStore.venues, tripStore: tripStore) {
                showManualCreate = false
            }
            .presentationDetents([.large])
            .presentationBackground(.black)
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip)
                .environmentObject(tripStore)
                .presentationDetents([.large])
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinByCodeView(
                joinCode: $joinCode,
                error: $joinError,
                isJoining: $isJoiningByCode
            ) {
                await joinByCode()
            }
            .presentationDetents([.height(360)])
            .presentationBackground(.black)
        }
    }

    @MainActor
    private func joinByCode() async {
        // Trim trailing whitespace / newline — a code pasted from Messages or
        // WhatsApp almost always carries one, and the server RPC trims too.
        let cleanCode = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { return }
        isJoiningByCode = true
        joinError = nil
        do {
            try await tripStore.joinByInviteCode(cleanCode)
            isJoiningByCode = false
            joinCode = ""
            showJoinByCode = false
        } catch {
            isJoiningByCode = false
            joinError = error.localizedDescription
        }
    }

    @MainActor
    private func createTripFromPrompt(title: String, venues: [BarPassVenue]) {
        let now = Date()
        let stops = Stop.sequence(for: venues, tripId: "", date: now)
        let trip = Trip(
            creatorId: TripStore.currentUserId,
            title: title,
            destinationCity: "Miami",
            startDate: now,
            endDate: now,
            visibility: .privateTrip,
            stops: stops
        )
        Task {
            await tripStore.create(trip)
            PointsEngine.shared.award(.createTrip)
            BPAnalytics.track(.createTrip)
        }
        showCreateFlow = false
    }
}

// MARK: - Trip → V2 card mapper

@MainActor
private extension Trip {
    var asV2CardModel: TripsListV2CardModel {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")

        let dateLabel = formatter.string(from: startDate).capitalized
        let memberCount = max(1, memberIds.count + 1)   // + creator
        let stopCount   = stops.count

        let sub = "\(dateLabel) · \(stopCount) parada\(stopCount == 1 ? "" : "s") · \(memberCount) miembro\(memberCount == 1 ? "" : "s")"

        let routeNames = stops.prefix(3).map { $0.venueName }
        let extraStops = max(0, stops.count - 3)
        let route = extraStops > 0
            ? routeNames + ["+\(extraStops)"]
            : routeNames

        let allMemberIds = ([creatorId] + memberIds).prefix(5)
        let avatars = allMemberIds.map { id -> TripsListV2Avatar in
            TripsListV2Avatar(
                color: TripsListV2Avatar.color(forSeed: id),
                initial: String(id.prefix(1)).uppercased()
            )
        }
        let extraMembers = max(0, memberCount - 5)

        let v2Status: TripsListV2Status
        let footer: String
        let footerTint: Color
        let dimmed: Bool

        switch status {
        case .active:
            v2Status = .active
            if let current = stops.first {
                footer = "PARADA 1 · \(current.venueName.prefix(14).uppercased())"
            } else {
                footer = "LIVE"
            }
            footerTint = Color.bpAmber
            dimmed = false
        case .planning:
            v2Status = .planning
            footer = stops.isEmpty ? "FALTA ARMAR RUTA" : "LISTO · POR CONFIRMAR"
            footerTint = Color.white.opacity(0.55)
            dimmed = false
        case .completed:
            v2Status = .completed
            footer = "COMPLETADO"
            footerTint = Color.white.opacity(0.5)
            dimmed = true
        }

        return TripsListV2CardModel(
            tripId: id,
            title: title,
            status: v2Status,
            sub: sub,
            route: route,
            avatars: avatars,
            extraMembers: extraMembers,
            footer: footer,
            footerTint: footerTint,
            dimmed: dimmed
        )
    }

    var asV2PublicRow: TripsListV2PublicSection.Row {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let dayLabel = formatter.string(from: startDate).capitalized
        let people = max(1, memberIds.count + 1)
        let stopsN = stops.count
        return TripsListV2PublicSection.Row(
            tripId: id,
            icon: emojiFor(title: title),
            name: title,
            detail: "\(dayLabel) · \(people) personas · \(stopsN) paradas"
        )
    }

    private func emojiFor(title: String) -> String {
        let t = title.lowercased()
        if t.contains("sunset")    { return "🌅" }
        if t.contains("rooftop")   { return "🏙️" }
        if t.contains("brickell")  { return "🌆" }
        if t.contains("beach")     { return "🏖️" }
        if t.contains("cumple") || t.contains("birthday") { return "🎂" }
        if t.contains("art")       { return "🎨" }
        return "🌃"
    }
}

private extension TripsListV2Avatar {
    /// Stable, legible color from any string seed (member user id).
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
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Empty / error subviews

@MainActor
private struct TripsListV2EmptyMyTrips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Todavía no tienes trips.")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Crea uno o únete con el código de un amigo.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

@MainActor
private struct TripsListV2ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No pude cargar tus trips")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(3)
            Button(action: { BPHaptics.selection(); onRetry() }) {
                Text("Reintentar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.bpAmber.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bpDanger.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Background (Miami eye + warm vignette + grain)

@MainActor
private struct TripsListV2Background: View {
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
                              y: proxy.size.height * -0.05)
                    .opacity(0.5)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.28),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Header

@MainActor
private struct TripsListV2Header: View {
    let planCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.bpAmber)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .fill(Color.bpAmberBright)
                                .frame(width: 3, height: 3)
                        )
                    Text("Trips · \(planCount) planes")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Color.bpAmber)
                }
                Spacer()
                TripsListV2Eye()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tus")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                Text("trips")
                    .font(.system(size: 40, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            }
            .padding(.top, 2)
        }
    }
}

/// The little vintage eye logo in the top-right of the header (mock SVG).
@MainActor
private struct TripsListV2Eye: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.18, green: 0.33, blue: 0.79))
                .frame(width: 32, height: 20)
            Capsule()
                .fill(Color(red: 0.91, green: 0.28, blue: 0.37))
                .frame(width: 28, height: 18)
            Circle()
                .fill(Color(red: 0.95, green: 0.82, blue: 0.29))
                .frame(width: 10, height: 10)
            Circle()
                .fill(Color(red: 0.1, green: 0.07, blue: 0.03))
                .frame(width: 5.5, height: 5.5)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 1.8, height: 1.8)
                        .offset(x: -1, y: -1)
                )
        }
        .frame(width: 36, height: 24)
    }
}

// MARK: - Action row

@MainActor
private struct TripsListV2ActionRow: View {
    var onJoin: () -> Void = {}
    var onCreate: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { BPHaptics.selection(); onJoin() }) {
                Text("Unirme con código")
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: { BPHaptics.selection(); onCreate() }) {
                HStack(spacing: 8) {
                    Text("Crear trip nuevo")
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bpAmberBright, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Trip card

private enum TripsListV2Status {
    case active, planning, completed

    var label: String {
        switch self {
        case .active: return "Activo"
        case .planning: return "Planeando"
        case .completed: return "Completado"
        }
    }

    var tagColor: Color {
        switch self {
        case .active: return Color.bpAmber
        case .planning: return Color(red: 0.85, green: 0.72, blue: 0.52)
        case .completed: return Color.white.opacity(0.5)
        }
    }

    var tagBackground: Color {
        switch self {
        case .active: return Color.bpAmber.opacity(0.18)
        case .planning: return Color.white.opacity(0.08)
        case .completed: return Color.white.opacity(0.05)
        }
    }

    var showLiveDot: Bool { self == .active }
}

private struct TripsListV2Avatar: Identifiable, Equatable {
    let id = UUID()
    let color: Color
    let initial: String
}

private struct TripsListV2CardModel: Identifiable {
    let id = UUID()
    /// Real backend id of the Trip this card represents.
    /// Nil only for the mockup previews.
    var tripId: String? = nil
    let title: String
    let status: TripsListV2Status
    let sub: String
    let route: [String]
    let avatars: [TripsListV2Avatar]
    let extraMembers: Int
    let footer: String
    let footerTint: Color
    let dimmed: Bool
}

@MainActor
private struct TripsListV2Card: View {
    let trip: TripsListV2CardModel
    /// Non-nil → the card renders inside a Button that forwards the tap.
    /// Nil → non-interactive (used by previews / debug menu).
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: { BPHaptics.selection(); onTap() }) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Toca para ver el detalle del trip")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(trip.dimmed ? Color.white.opacity(0.72) : .white)
                Spacer()
                TripsListV2StatusTag(status: trip.status)
            }

            Text(trip.sub)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))

            TripsListV2Route(stops: trip.route, dimmed: trip.dimmed)

            HStack(alignment: .center) {
                TripsListV2AvatarStack(avatars: trip.avatars, extra: trip.extraMembers)
                Spacer()
                Text(trip.footer)
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(trip.footerTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(trip.dimmed ? 0.025 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(trip.dimmed ? 0.06 : 0.09), lineWidth: 1)
        )
        .opacity(trip.dimmed ? 0.86 : 1.0)
    }
}

@MainActor
private struct TripsListV2StatusTag: View {
    let status: TripsListV2Status

    var body: some View {
        HStack(spacing: 5) {
            if status.showLiveDot {
                TripsListV2LiveDot()
            }
            Text(status.label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(status.tagColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tagBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(status.tagColor.opacity(0.3), lineWidth: 0.8))
    }
}

@MainActor
private struct TripsListV2LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.bpAmber)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Color.bpAmber, lineWidth: 1)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.9)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

@MainActor
private struct TripsListV2Route: View {
    let stops: [String]
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(stops.enumerated()), id: \.offset) { idx, s in
                Text(s)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dimmed ? Color.white.opacity(0.55) : Color.white.opacity(0.8))
                if idx < stops.count - 1 {
                    Text("→")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.bpAmber.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private struct TripsListV2AvatarStack: View {
    let avatars: [TripsListV2Avatar]
    let extra: Int

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(avatars.prefix(5).enumerated()), id: \.element.id) { idx, a in
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [a.color, a.color.opacity(0.65)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Text(a.initial)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .overlay(
                    Circle().strokeBorder(Color(red: 0.025, green: 0.015, blue: 0.04),
                                          lineWidth: 2)
                )
                .zIndex(Double(10 - idx))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color(red: 0.025, green: 0.015, blue: 0.04),
                                              lineWidth: 2)
                    )
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - Public trips section

@MainActor
private struct TripsListV2PublicSection: View {
    struct Row: Identifiable {
        let id = UUID()
        /// Backend id of the discoverable Trip this row represents.
        /// Nil only for mockup previews.
        var tripId: String? = nil
        let icon: String
        let name: String
        let detail: String
    }

    let rows: [Row]
    var onJoin: (Row) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Trips públicos para unirte")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.bpAmber)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    TripsListV2PublicRow(row: row, onJoin: { onJoin(row) })
                    if idx < rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

@MainActor
private struct TripsListV2PublicRow: View {
    let row: TripsListV2PublicSection.Row
    var onJoin: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text(row.icon)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { BPHaptics.selection(); onJoin() }) {
                Text("Unirme")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

// MARK: - Sample data (literals from mockup; TODO wire to TripStore)

extension TripsListV2Card {
    static let sampleActive = TripsListV2CardModel(
        title: "Noche en Wynwood",
        status: .active,
        sub: "Hoy · 3 paradas · 5 miembros",
        route: ["El Patio", "Amor Miami", "La Otra"],
        avatars: [
            .init(color: Color(red: 0.92, green: 0.72, blue: 0.28), initial: "M"),
            .init(color: Color(red: 0.55, green: 0.4,  blue: 0.95), initial: "J"),
            .init(color: Color(red: 0.2,  green: 0.9,  blue: 0.4),  initial: "A"),
            .init(color: Color(red: 0.93, green: 0.93, blue: 0.95), initial: "L"),
            .init(color: Color(red: 0.11, green: 0.11, blue: 0.13), initial: "D"),
        ],
        extraMembers: 0,
        footer: "PARADA 2 · AHORA",
        footerTint: Color.bpAmber,
        dimmed: false
    )

    static let samplePlanning = TripsListV2CardModel(
        title: "Cumple de Val",
        status: .planning,
        sub: "Sáb 17 oct · 2 paradas · 9 miembros",
        route: ["Sugar Rooftop", "Blackbird Ordinary"],
        avatars: [
            .init(color: Color(red: 0.11, green: 0.11, blue: 0.13), initial: "V"),
            .init(color: Color(red: 0.92, green: 0.72, blue: 0.28), initial: "C"),
            .init(color: Color(red: 0.55, green: 0.4,  blue: 0.95), initial: "T"),
            .init(color: Color(red: 0.2,  green: 0.9,  blue: 0.4),  initial: "R"),
        ],
        extraMembers: 5,
        footer: "FALTA ELEGIR HORA",
        footerTint: Color.white.opacity(0.55),
        dimmed: false
    )

    static let sampleCompleted = TripsListV2CardModel(
        title: "Art Basel weekend",
        status: .completed,
        sub: "6–8 dic · 5 paradas · 12 miembros",
        route: ["Club Space", "E11EVEN", "Lagniappe", "+2"],
        avatars: [
            .init(color: Color(red: 0.55, green: 0.4,  blue: 0.95), initial: "A"),
            .init(color: Color(red: 0.92, green: 0.72, blue: 0.28), initial: "B"),
            .init(color: Color(red: 0.11, green: 0.11, blue: 0.13), initial: "C"),
        ],
        extraMembers: 9,
        footer: "★ 4.8 · 12 RESEÑAS",
        footerTint: Color.white.opacity(0.5),
        dimmed: true
    )
}

#Preview {
    TripsListV2View()
        .environmentObject(VenueStore(repository: LocalVenueRepository()))
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
