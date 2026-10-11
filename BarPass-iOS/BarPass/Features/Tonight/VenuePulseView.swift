import SwiftUI

// VenuePulseView — pantalla 10 del artifact 294356f9 ("Venue con pulso").
//
// Traduce la sección "2 · La noche en vivo · Venue con pulso" (líneas
// 895–972 del mockup) al kit nativo. Reemplaza visualmente la vieja
// VenueDetailView (ficha estática) por una pantalla viva: cómo está AHORA
// un venue — curva de lleno, fila, qué suena, amigos adentro, lo que dice
// la gente hoy y el "take" de Remy con la mejor hora para entrar.
//
// Estilo heredado de OnboardingV2Flow (artifact 294356f9):
//   display  → .system(design: .rounded, weight: .black)
//   accent   → .system(design: .serif).italic()
//   eyebrow  → .system(design: .monospaced).tracking
// Fondo warm vignette + grain + eye-asset "CityArtMiami" al tope, en modo
// sutil (opacity 0.35) para no competir con la densidad de datos.
//
// Data wiring (2026-10-10):
//
// Esta pantalla cablea los datos REALES del venue (`BarPassVenue`) y los
// amigos que están adentro ahora (`FriendsTonightStore`). Las secciones
// cuyo backend NO existe hoy (curva de ocupación por hora, "voces" / crowd
// quotes, "take" de Remy con precio y hora exactos) se OCULTAN cuando se
// usa la inicialización real `init(venue:)` — mostrar números fabricados
// con cara de datos vivos ya nos costó caro (la saga de `music_genres`,
// CLAUDE.md). El preview debug de `ProfileView` sigue usando el init
// viejo con defaults mockup para que la galería de pantallas no pierda
// esa referencia visual.
//
// Decisión sobre `fillPercent` (preguntada por el task-brief): se dropea
// el número. No existe un medidor de aforo en vivo — mostrar "63%" con
// esa confianza es mentir. El header no muestra la columna y la pulsación
// del color amber en el nombre queda como "pulso" visual sin claim numérico.
//
// El status bar falso del mockup ("23:41 · SOS · 63%") se eliminó: iOS pinta
// el real, y el chip SOS de verdad vive en las pantallas de Safety.
//
// Release sólo compila `init(venue:)`. El init de mockup y las tres
// secciones sin backend (ocupación, voces, take de Remy) viven bajo
// `#if DEBUG` — igual que la galería de debug de ProfileView que las usa.
//
// Limitaciones aún presentes:
//   · No hay backend de ocupación por hora, voces, ni "take" de Remy — por
//     eso esas secciones no se dibujan en el camino real.
//   · El rayo-sol SVG del mockup (sun con 36 polígonos de colores) se
//     aproxima con el asset existente "CityArtMiami" + un cono amber en el
//     tope — equivalente visual sin cargar un SVG custom.
//   · Las fuentes del mockup (Bebas Neue, Instrument Serif, Courier Prime)
//     se aproximan con `.system(design:)` — mismo criterio que OnboardingV2.

@MainActor
struct VenuePulseView: View {
    @Environment(\.appStateIfPresent) private var appState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friendsStore = FriendsTonightStore.shared

    /// Real venue cuando se abre desde el flujo de la app. Nil sólo en los
    /// previews/debug (y por eso el init viejo sigue existiendo abajo).
    let venue: BarPassVenue?

    let venueName: String
    let subtitleAccent: String
    let openUntil: String
    let fillPercent: Int

    /// Sheet de VenueTabView — "Abrir cuenta" lo levanta cuando hay venue real.
    @State private var showTab = false

    // MARK: - Inits

    /// Entry point real: todo sale de `BarPassVenue`. Es el que usa MainTabView.
    init(venue: BarPassVenue) {
        self.venue = venue
        self.venueName = venue.name
        // El accent itálico queda bien con el barrio ("Boxcar · Wynwood")
        // cuando el nombre no se parte naturalmente en dos. Es la misma
        // decisión que ya traía la V1 (ver `MainTabView` hasta este commit).
        self.subtitleAccent = venue.neighborhood
        self.openUntil = venue.closeTime
        // El número del header se dropea en el camino real — el initializer
        // guarda 0 para que el estado interno siga teniendo valor, pero el
        // header no dibuja la columna cuando `venue != nil`.
        self.fillPercent = 0
    }

    #if DEBUG
    /// Preview init: deja la pantalla con los literales del mockup. Lo usa
    /// `ProfileView` (galería de debug) y los `#Preview` del final del
    /// archivo. No existe en Release.
    init(
        venueName: String = "Club",
        subtitleAccent: String = "Space",
        openUntil: String = "04:00",
        fillPercent: Int = 78
    ) {
        self.venue = nil
        self.venueName = venueName
        self.subtitleAccent = subtitleAccent
        self.openUntil = openUntil
        self.fillPercent = fillPercent
    }
    #endif

    // MARK: - Derived

    /// Camino real = hay un venue de verdad en el init. Las secciones que
    /// NO tienen backend hoy sólo se dibujan en el camino mockup — ver
    /// nota al inicio del archivo.
    private var isRealVenue: Bool { venue != nil }

    /// Amigos míos que están adentro ahora, según `get_friends_out_tonight`.
    /// Si no hay venue real o `FriendsTonightStore` todavía no cargó, es [].
    private var friendsInside: [FriendPresence] {
        guard let venue else { return [] }
        return friendsStore.friends(atVenue: venue.id)
    }

    /// "Ahora mismo" en la zona horaria del VENUE (`timezoneId`, que viene
    /// de la columna `timezone` del catálogo), porque `closeTime` es hora
    /// local del venue y las dos se leen juntas en el header. Si el venue
    /// no trae zona, cae a la del dispositivo — hoy el catálogo es Miami y
    /// el usuario casi siempre está ahí, pero no se promete "hora local".
    private var nowLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if let id = venue?.timezoneId, let tz = TimeZone(identifier: id) {
            f.timeZone = tz
        }
        return f.string(from: Date())
    }

    private var isOpenNow: Bool {
        guard let venue else { return true } // preview path keeps the mockup
        return venue.isOpenNow
    }

    var body: some View {
        ZStack {
            VPulseBackground()

            VStack(spacing: 0) {
                // iOS pinta el status bar real arriba de la safe area; este
                // spacer conserva el aire que ocupaba el chrome del mockup
                // para que el nav bar no suba.
                Spacer().frame(height: 20)
                VPulseNavBar(title: "\(venueName.uppercased()) \(subtitleAccent.uppercased())",
                             onBack: { dismiss() },
                             onShare: venue == nil ? nil : { shareVenue() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VPulseHeader(
                            venueName: venueName,
                            accent: subtitleAccent,
                            openUntil: openUntil,
                            isOpenNow: isOpenNow,
                            nowLabel: nowLabel,
                            fillPercent: isRealVenue ? nil : fillPercent
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        // Secciones sin backend (ocupación por hora, "voces",
                        // take de Remy): sólo existen en DEBUG y sólo se
                        // dibujan en el camino mockup. En Release ni se
                        // compilan — nunca mostramos números inventados.
                        #if DEBUG
                        if !isRealVenue {
                            VPulseOccupancyCard()
                                .padding(.horizontal, 20)
                        }
                        #endif

                        // Amigos adentro ahora: datos reales. Si no hay
                        // nadie, la card no se dibuja.
                        if !friendsInside.isEmpty {
                            VPulseFriendsCard(friends: friendsInside)
                                .padding(.horizontal, 20)
                        }

                        #if DEBUG
                        if !isRealVenue {
                            VPulseVoicesSection()
                                .padding(.top, 2)

                            VPulseRemyTake()
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                        }
                        #endif

                        Spacer().frame(height: 110) // room for sticky CTA
                    }
                    .padding(.bottom, 20)
                }
            }

            VStack {
                Spacer()
                VPulseStickyCTA(
                    onOpenTab: { openTab() },
                    onSkipLine: { openSkipLine() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Mismo evento que la V1 (VenueDetailView) — la ficha V2 cuenta
            // como "ver venue" para analytics.
            if let venue { BPAnalytics.track(.viewVenue(venue.id)) }
        }
        .task {
            // Dispara una vez al abrir — el store cachea por 60s, así que
            // volver desde otro screen no re-pega la RPC gratis.
            await friendsStore.refresh()
        }
        .sheet(isPresented: $showTab) {
            if let venue { VenueTabView(venue: venue) }
        }
    }

    // MARK: - CTA actions

    /// Exactamente lo que hace el botón de compartir de la V1
    /// (VenueDetailView): share sheet + analytics + XP.
    private func shareVenue() {
        guard let venue else { return }
        BPHaptics.light()
        ShareManager.present(ShareManager.shareVenue(venue))
        BPAnalytics.track(.shareVenue(venue: venue.id))
        PointsEngine.shared.award(.shareVenue)
    }

    private func openTab() {
        BPHaptics.medium()
        guard venue != nil else { return }
        showTab = true
    }

    /// Dispara el flujo Priority Entry (SkipLinePassView) exactamente como lo
    /// hace la V1: `appState.priorityVenueId/Name` + `showPriorityEntry = true`.
    /// Sin appState o sin venue, el botón no hace nada en vez de crashear.
    private func openSkipLine() {
        BPHaptics.medium()
        guard let venue, let appState else { return }
        appState.priorityVenueId = venue.id
        appState.priorityVenueName = venue.name
        appState.priorityEvent = nil
        appState.showPriorityEntry = true
    }
}

// MARK: - Background

@MainActor
private struct VPulseBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // The Miami eye at the top, same asset as OnboardingV2 — pushed
            // up high and dimmed, so it reads as a halo behind the big
            // percentage, not as a hero.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4,
                           height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.12)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            // Warm vignette halation
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 160, endRadius: 700
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade to black below the fold so content reads cleanly
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.18),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Nav bar

@MainActor
private struct VPulseNavBar: View {
    let title: String
    let onBack: () -> Void
    /// Nil en el camino mockup (no hay venue que compartir) → el botón no
    /// se dibuja. Un control visible siempre hace algo real.
    let onShare: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(3.2)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            if let onShare {
                Button(action: onShare) {
                    Text("Compartir")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.bpAmber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Header: ABIERTO/CERRADO · nombre + accent · (fillPercent only in preview)

@MainActor
private struct VPulseHeader: View {
    let venueName: String
    let accent: String
    let openUntil: String
    let isOpenNow: Bool
    let nowLabel: String
    /// En el camino real = nil (no hay medidor de aforo); el column no se
    /// dibuja. En el preview mockup, viene el número literal del mockup.
    let fillPercent: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(isOpenNow ? "ABIERTO" : "CERRADO")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(isOpenNow ? Color.bpGreen : Color.bpDanger)
                        .shadow(color: (isOpenNow ? Color.bpGreen : Color.bpDanger).opacity(0.45), radius: 6)

                    if isOpenNow && !openUntil.isEmpty {
                        Text("\(nowLabel) · cierra \(openUntil)")
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        Text(nowLabel)
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(venueName)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                    if !accent.isEmpty {
                        Text(accent)
                            .font(.system(size: 32, design: .serif).italic())
                            .foregroundStyle(Color.bpAmberBright)
                    }
                }
            }

            Spacer(minLength: 10)

            if let fillPercent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fillPercent)%")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .tracking(-1.2)
                        .foregroundStyle(Color.bpAmber)
                        .shadow(color: Color.bpAmber.opacity(0.4), radius: 10)
                    Text("lleno")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
    }
}

// MARK: - Occupancy card (curve + axis + chips) — mockup only, DEBUG only

#if DEBUG
@MainActor
private struct VPulseOccupancyCard: View {
    // Hours 22..04 → percentages matching the "pico 01:30–03:00" peak.
    // Index of "ahora" (23 bucket) is 1.
    private let hours: [String] = ["22", "23", "ahora", "01", "02", "03", "04"]
    private let fills: [CGFloat] = [0.28, 0.46, 0.78, 0.90, 1.0, 0.95, 0.58]
    private let nowIndex: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cómo se llena hoy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
                Text("pico 01:30–03:00")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.bpAmber)
            }

            VPulseBarChart(fills: fills, nowIndex: nowIndex)
                .frame(height: 86)

            VPulseAxisRow(labels: hours, highlightIndex: nowIndex)

            VPulseChipRow(chips: [
                .init(icon: "clock", text: "fila 20 min", amber: false),
                .init(icon: "waveform", text: "sonando techno", amber: false),
                .init(icon: "slider.horizontal.3", text: "Mejor hora: ahora", amber: true),
            ])
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
    }
}

@MainActor
private struct VPulseBarChart: View {
    let fills: [CGFloat]
    let nowIndex: Int

    var body: some View {
        GeometryReader { geo in
            let barCount = fills.count
            let spacing: CGFloat = 10
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(barCount), 10)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(fills.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barFill(i))
                            .frame(width: barWidth,
                                   height: max(geo.size.height * fills[i], 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(
                                        i == nowIndex ? Color.bpAmberBright : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: i == nowIndex ? Color.bpAmber.opacity(0.55) : .clear,
                                radius: 8
                            )
                    }
                }
            }
        }
    }

    private func barFill(_ i: Int) -> LinearGradient {
        if i == nowIndex {
            return LinearGradient(
                colors: [Color.bpAmberBright, Color.bpAmber],
                startPoint: .top, endPoint: .bottom
            )
        }
        if i < nowIndex {
            return LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Color.bpAmber.opacity(0.55), Color.bpAmber.opacity(0.22)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

@MainActor
private struct VPulseAxisRow: View {
    let labels: [String]
    let highlightIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(i == highlightIndex ? Color.bpAmber : Color.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct VPulseChip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let amber: Bool
}

@MainActor
private struct VPulseChipRow: View {
    let chips: [VPulseChip]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips) { c in
                HStack(spacing: 5) {
                    Image(systemName: c.icon)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(c.amber ? Color.bpAmber : Color.white.opacity(0.75))
                    Text(c.text)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(c.amber ? Color.bpAmberBright : Color.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(
                    c.amber
                        ? Color.bpAmber.opacity(0.18)
                        : Color.white.opacity(0.06),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        c.amber ? Color.bpAmber.opacity(0.4) : Color.white.opacity(0.1)
                    )
                )
            }
            Spacer(minLength: 0)
        }
    }
}
#endif

// MARK: - Friends card (avstack · texto) — real FriendsTonightStore data

@MainActor
private struct VPulseFriendsCard: View {
    let friends: [FriendPresence]

    /// "Mía y Jules adentro" / "Mía adentro" / "4 amigos adentro". Nunca
    /// fabricamos nombres: el store sabe cuáles son.
    private var leadLine: String {
        switch friends.count {
        case 0:
            return ""
        case 1:
            return "\(friends[0].name) adentro"
        case 2:
            return "\(friends[0].name) y \(friends[1].name) adentro"
        default:
            return "\(friends.count) amigos adentro"
        }
    }

    /// Hora de llegada del primero (desde cuándo está adentro). Es un dato
    /// real que viene de `checkedInAt`. Si por algún motivo no hay primero,
    /// no se dibuja la segunda línea.
    private var sinceLine: String? {
        guard let first = friends.first else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "desde \(f.string(from: first.checkedInAt))"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar stack — hasta 2 superpuestos, mismo tratamiento que
            // el mockup. `FriendAvatar` es el helper que ya se usa en
            // ExploreView.
            HStack(spacing: -10) {
                ForEach(Array(friends.prefix(2).enumerated()), id: \.element.id) { pair in
                    FriendAvatar(
                        name: pair.element.name,
                        url: pair.element.avatarUrl,
                        config: pair.element.avatarConfig,
                        size: 36
                    )
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    .zIndex(Double(2 - pair.offset))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let sinceLine {
                    Text("\(leadLine) · \(sinceLine)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                } else {
                    Text(leadLine)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                // La segunda línea del mockup ("+ 6 personas que conoces
                // estuvieron este mes") NO tiene backend de historial de
                // visitas hoy — se omite en vez de inventar un número.
            }

            // El pill "Ir" del mockup se quitó: estos amigos están EN ESTE
            // venue (la card filtra por `venue.id`), así que no hay otro
            // lugar al que ir. Un control que no hace nada es un defecto.
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Voices section ("Lo que dice la gente hoy") — mockup only, DEBUG only

#if DEBUG
@MainActor
private struct VPulseVoicesSection: View {
    private let voices: [VPulseVoice] = [
        .init(stamp: "23:30 · Leo",
              body: "\"terraza abierta, adentro ya está lleno\""),
        .init(stamp: "23:12",
              body: "\"$18 el trago, cover $20 antes de la 1\""),
        .init(stamp: "22:50",
              body: "\"la fila va rápido con el pase\""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lo que dice la gente hoy")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("14 hoy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(voices) { v in
                        VPulseVoiceCard(voice: v)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct VPulseVoice: Identifiable {
    let id = UUID()
    let stamp: String
    let body: String
}

@MainActor
private struct VPulseVoiceCard: View {
    let voice: VPulseVoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(voice.stamp)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.5))
            Text(voice.body)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Remy's amber "take" — mockup only

@MainActor
private struct VPulseRemyTake: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.bpAmber)
                    .frame(width: 32, height: 32)
                Text("R")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Remy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.65))

                // Mockup: "Entras en tu $31 si pides 1 trago. Con Skip the Line
                // entras a las 00:45 sin fila." — copy neutro (sin voseo) por
                // la regla de UI del proyecto. Literales sólo en DEBUG.
                (
                    Text("Entras en tu ").foregroundStyle(Color.white.opacity(0.85)) +
                    Text("$31").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white) +
                    Text(" si pides 1 trago. Con Skip the Line entras ")
                        .foregroundStyle(Color.white.opacity(0.85)) +
                    Text("a las 00:45 sin fila.").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                )
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.bpAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.35)))
    }
}
#endif

// MARK: - Sticky bottom CTA ("Abrir cuenta" + "Skip the Line · desde $X")

@MainActor
private struct VPulseStickyCTA: View {
    let onOpenTab: () -> Void
    let onSkipLine: () -> Void

    /// Precio del pase individual — la MISMA fuente que cobra
    /// `SkipLinePassView` (`PassOption.solo.price`), nunca un literal
    /// duplicado. "desde" porque pareja/grupo cuestan más.
    private var priceLabel: String {
        let price = SkipLinePassView.PassOption.solo.price
        let amount = price.rounded() == price
            ? String(Int(price))
            : String(format: "%.2f", price)
        return "desde $\(amount)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenTab) {
                Text("Abrir cuenta")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)

            Button(action: onSkipLine) {
                HStack(spacing: 6) {
                    Text("Skip the Line")
                    Text("·").foregroundStyle(.black.opacity(0.5))
                    Text(priceLabel)
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VenuePulseView()
        .environmentObject(AppState())
}
#endif
