import SwiftUI

// NightRecapView — "Recap y racha" (pantalla 11 del artifact 294356f9, 2026-10-09).
// La mañana siguiente a una noche: tu noche en números + polaroids, racha de
// fines de semana, una pregunta de precio (alimenta el catálogo), y Remy ya
// prepara el viernes.
//
// Esta pantalla es NUEVA — no reemplaza nada. Se presenta como push o sheet
// desde el stack post-noche (p.ej. al abrir la app un sábado AM después de un
// viernes activo).
//
// Qué es real vs stub (2026-10-10, pase de cableo real):
//   - Paradas, duración, polaroids: desde `venue_checkins` del propio usuario
//     (RLS "read own"), filtradas a la ventana "anoche" (ayer 18:00 → hoy
//     06:00 en hora local). Las polaroids ya no cargan foto porque
//     `venue_media` no expone `user_id` al cliente (location history) — se
//     mantiene el gradiente del mockup y se nota en el header de PolaroidView.
//   - Gasto: suma de `OrderHistoryService.fetchOrders()` dentro de la ventana,
//     sólo filas con status succeeded/completed/paid. Si no hubo compras en
//     la app, el tile "GASTADO" se oculta (la ausencia no se rinde como "$0").
//   - XP: sólo lo que PointsEngine define — `XPAction.checkIn.xp` por parada.
//     No hay XPAction por gastar ni por reportar precio, así que no se
//     promete ninguno. PointsEngine server-side todavía no expone un total
//     por noche; cuando lo haga, se reemplaza este cálculo.
//   - Noche sólo con pedidos (sin check-ins): duración y paradas son
//     desconocidas, no cero. Se ocultan el título de duración, los tiles de
//     PARADAS/XP y la fila de polaroids; el título pasa a ser el gasto real.
//   - Racha: cuenta fines de semana distintos (viernes/sábado/domingo, ISO
//     week) con al menos un check-in en los últimos 42 días. Es por tanto
//     real y acumulativa, no un número fijo.
//   - Pregunta de precio y venue referido ("Club Space"): el venue ya no es
//     literal — se usa la última parada de la noche, resuelta por id contra
//     el catálogo (VenueStore y, si no está en la ciudad cargada,
//     `RepositoryDependencies.venue.getVenue(id:)`). Si no se resuelve, la
//     tarjeta no se muestra. El tap escribe de verdad en
//     `venue_price_reports` vía `SupabasePriceReportRepository` y el
//     "gracias" aparece sólo cuando el POST terminó bien.
//   - Nombres de venue en polaroids/share: mismo resolver por id. Si un id
//     no resuelve, la polaroid muestra sólo la hora (nunca "Venue").
//   - "Amigos anoche" / caption "con Mía y Jules" del artifact: NO se cablea.
//     El servidor expone sólo `get_friends_out_tonight()` (presencia actual),
//     no un barrido histórico de "quién estaba contigo anoche" (friendships
//     + venue_checkins requieren join cross-user que RLS bloquea a propósito).
//     La vista no muestra captions de amigos hasta que exista una RPC
//     equivalente.
//   - Share: ShareManager.present(...) con texto "Mi noche en BarPass · N
//     lugares · {rutas}". Se expone por long-press en la fila de polaroids
//     (contextMenu "Compartir noche") para no agregar botón al diseño sacro.
//   - Empty state: cuando no hubo check-ins ni órdenes, se muestra una vista
//     digna (sin inventar paradas). Mantiene el background y la familia
//     visual.
//
// Fuentes: usa .system con design/weight/tracking como el resto de la familia
// (OnboardingV2Flow). Nada de Bebas / Instrument Serif / Courier Prime en el
// bundle todavía.

import Foundation

// MARK: - Data

/// Momento del itinerario anoche (una polaroid).
struct NightRecapMoment: Identifiable, Equatable {
    let id = UUID()
    /// Nombre del venue en mayúsculas ("SUGAR"). `nil` cuando el id del
    /// check-in no resolvió contra el catálogo — la polaroid muestra sólo
    /// la hora en ese caso, nunca un placeholder.
    let venueName: String?
    let time: String        // "22:14"
    let tint: Color         // color del film sintético

    /// Caption real de la polaroid: "SUGAR · 22:14", o sólo "22:14".
    var caption: String {
        [venueName, time].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Datos reales para armar la vista. Todo campo que puede no existir es
/// opcional y la vista oculta el bloque correspondiente: nada se rinde
/// como "0", "$0" ni "Venue".
struct NightRecapData: Equatable {
    var dateLabel: String                // "SÁB 10 OCT"
    /// Minutos entre el primer check-in y el último check-out. `nil` cuando
    /// no hubo check-ins (noche sólo con pedidos): la duración es
    /// desconocida, no cero.
    var durationTotalMinutes: Int?
    /// Cantidad de check-ins. 0 => sin paradas registradas (tile oculto).
    var stops: Int
    /// Suma de pedidos pagados en la app dentro de la ventana. `nil` cuando
    /// no hubo ninguno (tile oculto).
    var dollarsSpent: Int?
    /// XP según `XPAction.checkIn.xp` × paradas. 0 => tile oculto.
    var xpEarned: Int
    var moments: [NightRecapMoment]
    var streakWeekends: Int              // 2
    var streakHint: String               // "El viernes mantiene la racha · Remy ya tiene 2 ideas"
    /// Última parada de la noche, resuelta contra el catálogo. Ambos `nil`
    /// cuando no hay check-in o el id no resolvió (tarjeta oculta).
    var askVenueId: String?
    var askVenueName: String?            // "Club Space"
    var fridayCTA: String                // "Ver el plan del viernes"

    var durationHours: Int? { durationTotalMinutes.map { $0 / 60 } }
    var durationMinutes: Int? { durationTotalMinutes.map { $0 % 60 } }

    #if DEBUG
    /// Sample data for SwiftUI previews y para el botón "Recap y racha" del
    /// debug tray en Profile. Nunca se renderiza en producción: la ruta
    /// pública es `NightRecapView()` sin argumentos, que carga datos reales.
    static let mockup = NightRecapData(
        dateLabel: "SÁB 10 OCT",
        durationTotalMinutes: 4 * 60 + 12,
        stops: 3,
        dollarsSpent: 67,
        xpEarned: 3 * XPAction.checkIn.xp,
        moments: [
            .init(venueName: "SUGAR",     time: "22:14",
                  tint: Color(red: 0.42, green: 0.18, blue: 0.42)),
            .init(venueName: "BLACKBIRD", time: "23:40",
                  tint: Color(red: 0.18, green: 0.12, blue: 0.08)),
            .init(venueName: "SPACE",     time: "02:05",
                  tint: Color(red: 0.5,  green: 0.22, blue: 0.1)),
        ],
        streakWeekends: 2,
        streakHint: "El viernes mantiene la racha · Remy ya tiene 2 ideas",
        askVenueId: "00000000-0000-0000-0000-000000000000",
        askVenueName: "Club Space",
        fridayCTA: "Ver el plan del viernes"
    )
    #endif
}

// MARK: - Store (real data loader)

/// Carga la noche recién terminada del usuario desde Supabase y Order history.
/// Agrega check-ins + órdenes dentro de la ventana "anoche" en hora local
/// (más reciente 18:00 → 06:00 siguiente que ya cerró), resuelve nombres de
/// venue con `VenueStore`, y calcula racha de fines de semana con 42 días
/// de check-ins. Nada se inventa: si no hubo salida registrada, pasa a
/// `.empty` para que la vista muestre su estado digno.
@MainActor
final class NightRecapStore: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(NightRecapData)
        case empty
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var shareText: String = ""

    private(set) var venueStore: VenueStore

    init(venueStore: VenueStore) {
        self.venueStore = venueStore
    }

    /// La vista crea el `@StateObject` antes de poder leer `@EnvironmentObject`,
    /// así que acá se enlaza el `VenueStore` real del ambiente justo antes
    /// de cargar. Idempotente — llamar dos veces con el mismo store no cambia
    /// nada.
    func bind(venueStore: VenueStore) {
        self.venueStore = venueStore
    }

    // MARK: Ventana "anoche"

    /// Más reciente ventana noche-completa, cerrada ya. En hora local:
    ///   · si `now ≥ 06:00` de hoy      → ayer 18:00 → hoy 06:00
    ///   · si `now < 06:00` de hoy      → anteayer 18:00 → ayer 06:00
    /// (6am es el mismo boundary que usan stories / `bp_night_of`.)
    static func lastNightWindow(now: Date = Date(),
                                calendar: Calendar = .current) -> (start: Date, end: Date) {
        var endComps = calendar.dateComponents([.year, .month, .day], from: now)
        endComps.hour = 6; endComps.minute = 0; endComps.second = 0
        var end = calendar.date(from: endComps) ?? now
        if now < end {
            end = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        }
        let start = calendar.date(byAdding: .hour, value: -12, to: end) ?? end.addingTimeInterval(-12 * 3600)
        return (start, end)
    }

    // MARK: Load

    func load() async {
        state = .loading

        let (start, end) = Self.lastNightWindow()

        async let checkinsTask = Self.fetchCheckins(start: start, end: end)
        async let ordersTask: [OrderHistoryService.OrderRow] = {
            // Las órdenes no fallan la carga de la noche: una lista vacía
            // es un hecho válido (muchos recaps son sin compras en-app).
            (try? await OrderHistoryService.fetchOrders()) ?? []
        }()
        async let streakTask: Int = (try? await Self.weekendStreak()) ?? 0

        let checkins: [CheckinRow]
        do {
            checkins = try await checkinsTask
        } catch {
            // Si la red falló, no mostramos un recap falso; se ofrece reintentar.
            state = .failed(error.localizedDescription)
            _ = await ordersTask
            _ = await streakTask
            return
        }

        let orders = await ordersTask
        let streak = await streakTask

        let ordersInWindow = orders.filter {
            $0.created_at >= start && $0.created_at < end
        }

        // Gasto: sólo filas pagadas. Los status que el backend emite son
        // "succeeded" (Stripe PaymentIntent) y, para datos legacy,
        // "completed"/"paid".
        let paidStatuses: Set<String> = ["succeeded", "completed", "paid"]
        let paidOrders = ordersInWindow.filter { paidStatuses.contains($0.status.lowercased()) }
        let spendRounded = Int(paidOrders.reduce(0.0) { $0 + $1.total }.rounded())
        // `nil` = no hubo compras pagadas en la app. Nunca "$0".
        let dollarsSpent: Int? = (paidOrders.isEmpty || spendRounded <= 0) ? nil : spendRounded

        if checkins.isEmpty && dollarsSpent == nil {
            state = .empty
            shareText = ""
            return
        }

        // Nombres de venue por id: primero la ciudad ya cargada en
        // VenueStore, después el repositorio (puede tener más ciudades en
        // caché). Un id que no resuelve queda `nil` — nunca "Venue".
        var namesById: [String: String] = [:]
        for id in Set(checkins.map(\.venueId)) {
            if let name = await resolveVenueName(id: id) {
                namesById[id] = name
            }
        }

        let moments: [NightRecapMoment] = checkins.enumerated().map { idx, c in
            NightRecapMoment(
                venueName: namesById[c.venueId]?.uppercased(),
                time: Self.hhmm(c.checkedInAt),
                tint: Self.polaroidTint(index: idx)
            )
        }

        // Duración: desde el primer check-in hasta el último check-out, o
        // hasta el fin de ventana / "now" si el último sigue abierto. Sin
        // check-ins no hay duración que medir — queda `nil`, no "0 h 00".
        let durationTotalMinutes: Int? = {
            guard let first = checkins.first, let last = checkins.last else { return nil }
            let lastKnownEnd = last.checkedOutAt ?? min(end, Date())
            let elapsed = max(0, lastKnownEnd.timeIntervalSince(first.checkedInAt))
            return Int(elapsed) / 60
        }()

        // La fecha del recap: el primer check-in, o la primera compra si la
        // noche fue sólo pedidos.
        let anchorDate = checkins.first?.checkedInAt
            ?? paidOrders.map(\.created_at).min()
            ?? start

        // XP: exactamente lo que PointsEngine otorga por check-in. No existe
        // XPAction por gastar, así que no se suma nada por eso.
        let xp = checkins.count * XPAction.checkIn.xp

        // askVenue = la última parada (típicamente el nightclub de la noche),
        // sólo si su nombre resolvió.
        let askVenueId: String? = checkins.last.flatMap { namesById[$0.venueId] != nil ? $0.venueId : nil }
        let askVenueName: String? = askVenueId.flatMap { namesById[$0] }

        let data = NightRecapData(
            dateLabel: Self.dateLabel(for: anchorDate),
            durationTotalMinutes: durationTotalMinutes,
            stops: checkins.count,
            dollarsSpent: dollarsSpent,
            xpEarned: xp,
            moments: moments,
            streakWeekends: streak,
            streakHint: Self.streakHint(for: streak),
            askVenueId: askVenueId,
            askVenueName: askVenueName,
            fridayCTA: Self.ctaForToday()
        )
        state = .loaded(data)
        shareText = Self.buildShareText(stops: checkins.count, moments: moments)
    }

    /// Resuelve un venue por id: VenueStore (ciudad activa) y luego el
    /// repositorio real. Devuelve `nil` si nadie lo conoce.
    private func resolveVenueName(id: String) async -> String? {
        if let name = venueStore.venues.first(where: { $0.id == id })?.name,
           !name.isEmpty {
            return name
        }
        let repository = RepositoryDependencies.venue
        if let venue = try? await repository.getVenue(id: id), !venue.name.isEmpty {
            return venue.name
        }
        return nil
    }

    // MARK: Price report

    /// Escribe el reporte de precio en `venue_price_reports`. Lanza si el
    /// POST falla — la vista muestra el "gracias" sólo cuando esto vuelve.
    func reportDrinkPrice(venueId: String, cents: Int) async throws {
        let repository: any PriceReportRepository = SupabasePriceReportRepository()
        try await repository.reportDrinkPrice(venueId: venueId, cents: cents)
    }

    // MARK: Fetching

    fileprivate struct CheckinRow: Decodable {
        let id: String
        let venueId: String
        let tripId: String?
        let checkedInAt: Date
        let checkedOutAt: Date?
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func fetchCheckins(start: Date, end: Date) async throws -> [CheckinRow] {
        let session = try await SupabaseRESTClient.freshSession()
        let startStr = timestampFormatter.string(from: start)
        let endStr   = timestampFormatter.string(from: end)
        let request = try SupabaseRESTClient.request(
            "GET", path: "venue_checkins",
            queryItems: [
                URLQueryItem(name: "select", value: "id,venue_id,trip_id,checked_in_at,checked_out_at"),
                // RLS filter will scope to the signed-in user; this just
                // bounds the window.
                URLQueryItem(name: "checked_in_at", value: "gte.\(startStr)"),
                URLQueryItem(name: "checked_in_at", value: "lt.\(endStr)"),
                URLQueryItem(name: "order", value: "checked_in_at.asc"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([CheckinRow].self, from: data)
    }

    private static func weekendStreak() async throws -> Int {
        let session = try await SupabaseRESTClient.freshSession()
        let since = Calendar.current.date(byAdding: .day, value: -42, to: Date())
            ?? Date().addingTimeInterval(-42 * 86_400)
        let request = try SupabaseRESTClient.request(
            "GET", path: "venue_checkins",
            queryItems: [
                URLQueryItem(name: "select", value: "checked_in_at"),
                URLQueryItem(name: "checked_in_at", value: "gte.\(timestampFormatter.string(from: since))"),
                URLQueryItem(name: "order", value: "checked_in_at.asc"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct TS: Decodable { let checkedInAt: Date }
        let rows = try SupabaseRESTClient.decoder.decode([TS].self, from: data)
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        var weekends: Set<String> = []
        for r in rows {
            // Friday (6), Saturday (7), Sunday (1) in Gregorian weekday.
            let weekday = Calendar.current.component(.weekday, from: r.checkedInAt)
            guard [1, 6, 7].contains(weekday) else { continue }
            let yWeek = cal.component(.yearForWeekOfYear, from: r.checkedInAt)
            let week  = cal.component(.weekOfYear,        from: r.checkedInAt)
            weekends.insert("\(yWeek)-\(week)")
        }
        return weekends.count
    }

    // MARK: Formatting

    private static func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func dateLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date).uppercased()
    }

    private static func polaroidTint(index: Int) -> Color {
        // Mismos tintes del mockup, cicleados: morado profundo / tabaco /
        // naranja quemado. Son del film, no del venue — por eso rotan por índice.
        let palette: [Color] = [
            Color(red: 0.42, green: 0.18, blue: 0.42),
            Color(red: 0.18, green: 0.12, blue: 0.08),
            Color(red: 0.50, green: 0.22, blue: 0.10),
            Color(red: 0.22, green: 0.28, blue: 0.42),
            Color(red: 0.38, green: 0.14, blue: 0.22),
        ]
        return palette[index % palette.count]
    }

    private static func streakHint(for streakWeekends: Int) -> String {
        switch streakWeekends {
        case 0:
            return "La próxima noche arranca la racha."
        case 1:
            return "Primer fin de semana. La próxima la hace cadena."
        case 2:
            return "Dos fines de semana al hilo. Remy ya está pensando el próximo."
        default:
            return "\(streakWeekends) fines de semana al hilo. Impresionante."
        }
    }

    private static func ctaForToday() -> String {
        // El CTA del mockup era "Ver el plan del viernes". Al cablear real,
        // se usa el próximo weekend day desde hoy. En es-ES los días son
        // minúsculas sin tildes raras.
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE"
        let today = Calendar.current.component(.weekday, from: Date())
        // Elegimos el próximo viernes/sábado como "la noche grande" relativa.
        let target: String
        switch today {
        case 6, 7:  // viernes, sábado — es hoy mismo o esta noche
            target = "esta noche"
        case 1:     // domingo
            target = "el próximo viernes"
        default:
            target = "el viernes"
        }
        return "Ver el plan de \(target)"
    }

    private static func buildShareText(stops: Int, moments: [NightRecapMoment]) -> String {
        guard stops > 0 else { return "Mi noche en BarPass" }
        // Sólo nombres resueltos: un id desconocido no entra a la ruta.
        let route = moments.compactMap { $0.venueName?.capitalized }.joined(separator: " → ")
        let label = stops == 1 ? "lugar" : "lugares"
        if route.isEmpty { return "Mi noche en BarPass · \(stops) \(label)" }
        return "Mi noche en BarPass · \(stops) \(label) · \(route)"
    }
}

// MARK: - Entry view

@MainActor
struct NightRecapView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var venueStore: VenueStore

    /// Si se pasa, la vista rinde esos datos tal cual (ruta debug / preview).
    /// Si es nil, se arma un `NightRecapStore` al vuelo contra Supabase.
    private let injectedData: NightRecapData?
    private let onDismiss: () -> Void

    @StateObject private var store: NightRecapStore
    /// Nada pre-marcado: una respuesta que el usuario no dio no se muestra.
    @State private var selectedPricePill: Int? = nil
    @State private var priceReport: PriceReportState = .idle
    @State private var appearStage: Int = 0

    /// Ciclo del reporte de precio. El "gracias" existe sólo en `.sent`,
    /// es decir, después de que el POST a `venue_price_reports` volvió bien.
    private enum PriceReportState: Equatable {
        case idle
        case sending
        case sent
        case declined   // "no sé": no hay nada que reportar
        case failed
    }

    init(data: NightRecapData? = nil,
         onDismiss: @escaping () -> Void = {}) {
        self.injectedData = data
        self.onDismiss = onDismiss
        // El VenueStore se inyecta vía @EnvironmentObject al render, pero
        // StateObject necesita un init concreto; lo construimos sin stores
        // reales acá y la carga usa `venueStore` desde el ambiente antes de
        // llamar a `load()`. Como `load()` corre con el venueStore de la
        // vista, es el mismo que ya se inyectó en el ambiente.
        _store = StateObject(wrappedValue: NightRecapStore(venueStore: VenueStore()))
    }

    /// Pill → centavos que se guardan en `venue_price_reports`. "$22+" se
    /// registra en su piso (2200): es lo único que el usuario afirmó. "no sé"
    /// no reporta nada (`nil`).
    private let pricePills: [(label: String, cents: Int?)] = [
        ("$12", 1200), ("$15", 1500), ("$18", 1800), ("$22+", 2200), ("no sé", nil),
    ]

    var body: some View {
        ZStack {
            RecapBackground()

            Group {
                if let injectedData {
                    recapContent(data: injectedData)
                } else {
                    switch store.state {
                    case .loading:
                        loadingView
                    case .loaded(let data):
                        recapContent(data: data)
                    case .empty:
                        NightRecapEmptyView(onDismiss: onDismiss)
                    case .failed(let message):
                        NightRecapErrorView(message: message) {
                            Task { await store.load() }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Nada que cargar cuando el caller inyectó datos (preview/debug).
            guard injectedData == nil else { return }
            // El store se construyó con un VenueStore vacío (StateObject no
            // puede ver el @EnvironmentObject hasta render). Reemplazamos la
            // referencia por el store real del ambiente antes de cargar, así
            // los nombres de venue se resuelven.
            store.bind(venueStore: venueStore)
            await store.load()
        }
        .onAppear { animateIn() }
    }

    @ViewBuilder
    private func recapContent(data: NightRecapData) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 70)

                header(data: data)
                titleBlock(data: data)
                statsRow(data: data)
                polaroidsRow(data: data)
                streakCard(data: data)
                askCard(data: data)
                ctaButton(data: data)

                Spacer().frame(height: 48)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(Color.bpAmber)
                .scaleEffect(1.2)
            Text("Armando tu recap…")
                .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Color.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header (eyebrow + fecha ticket)

    private func header(data: NightRecapData) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
                Text("Tu noche de ayer")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.bpAmber)
            }
            Spacer()
            Text(data.dateLabel)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.bpAmberBright, in: RoundedRectangle(cornerRadius: 3))
                .rotationEffect(.degrees(2))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                        .rotationEffect(.degrees(2))
                )
        }
        .padding(.horizontal, 24)
        .opacity(appearStage >= 1 ? 1 : 0)
        .offset(y: appearStage >= 1 ? 0 : 8)
    }

    // MARK: - Título (mezcla sans + serif italic)

    /// Hero: "4 h 12 de noche" cuando hubo check-ins. Si la noche fue sólo
    /// pedidos (duración desconocida), el hero pasa a ser el gasto real
    /// ("$67 en pedidos") y el tile GASTADO se omite para no repetirlo. Si no
    /// hay ni lo uno ni lo otro, el bloque no se dibuja (el store ya habría
    /// pasado a `.empty`, pero no se asume).
    @ViewBuilder
    private func titleBlock(data: NightRecapData) -> some View {
        if let hours = data.durationHours, let minutes = data.durationMinutes {
            heroLine(big: "\(hours) h \(String(format: "%02d", minutes))", tail: "de noche")
        } else if let dollars = data.dollarsSpent {
            heroLine(big: "$\(dollars)", tail: "en pedidos")
        }
    }

    private func heroLine(big: String, tail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(big)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .tracking(-1.6)
                .foregroundStyle(.white)
            Text(tail)
                .font(.system(size: 32, design: .serif).italic())
                .foregroundStyle(Color.bpAmberBright)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .opacity(appearStage >= 1 ? 1 : 0)
        .offset(y: appearStage >= 1 ? 0 : 12)
    }

    // MARK: - Stats (hasta 3; cada tile sólo si hay dato real detrás)

    /// Tiles con fuente real. PARADAS/XP necesitan check-ins; GASTADO
    /// necesita compras pagadas y no se repite si ya es el hero.
    private func statTiles(data: NightRecapData) -> [(big: String, small: String, tint: Color)] {
        var tiles: [(big: String, small: String, tint: Color)] = []
        let hasCheckins = data.stops > 0 && data.durationTotalMinutes != nil
        if hasCheckins {
            tiles.append((big: "\(data.stops)", small: "PARADAS", tint: .white))
        }
        if let dollars = data.dollarsSpent, hasCheckins {
            tiles.append((big: "$\(dollars)", small: "GASTADO", tint: Color.bpAmber))
        }
        if data.xpEarned > 0 {
            tiles.append((big: "+\(data.xpEarned)", small: "XP", tint: Color.bpAmberBright))
        }
        return tiles
    }

    @ViewBuilder
    private func statsRow(data: NightRecapData) -> some View {
        let tiles = statTiles(data: data)
        if !tiles.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    RecapStat(big: tile.big, small: tile.small, tint: tile.tint)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .opacity(appearStage >= 2 ? 1 : 0)
            .offset(y: appearStage >= 2 ? 0 : 10)
        }
    }

    // MARK: - Polaroids

    @ViewBuilder
    private func polaroidsRow(data: NightRecapData) -> some View {
        // Sin check-ins no hay momentos: la fila no se dibuja.
        if !data.moments.isEmpty {
            polaroidsScroller(data: data)
        }
    }

    private func polaroidsScroller(data: NightRecapData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(data.moments.enumerated()), id: \.element.id) { idx, m in
                    PolaroidView(moment: m, rotation: polaroidRotation(for: idx))
                        .opacity(appearStage >= 3 ? 1 : 0)
                        .offset(y: appearStage >= 3 ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75)
                                    .delay(0.05 * Double(idx)),
                                   value: appearStage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .padding(.top, 20)
        // Share CTA sin agregar botón: long-press sobre la fila de polaroids
        // abre el menú del sistema con "Compartir noche". Mantiene el diseño
        // intacto pero deja la acción accesible.
        .contextMenu {
            Button {
                shareNight()
            } label: {
                Label("Compartir noche", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func polaroidRotation(for idx: Int) -> Double {
        // Pequeño desorden para que luzcan como fotos tiradas en la mesa.
        let seeds: [Double] = [-3, 2, -1.5]
        return seeds[idx % seeds.count]
    }

    // MARK: - Racha

    /// Racha real (fines de semana distintos con check-in en 42 días). Con 0
    /// no se dibuja: un "0 fines de semana" es una ausencia rendida como
    /// valor.
    @ViewBuilder
    private func streakCard(data: NightRecapData) -> some View {
        if data.streakWeekends > 0 {
            streakCardBody(data: data)
        }
    }

    private func streakCardBody(data: NightRecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Racha")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(data.streakWeekends)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(-1.4)
                    .foregroundStyle(Color.bpAmberBright)
                Text("fines de semana")
                    .font(.system(size: 20, design: .serif).italic())
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                // Mini bar visual: 2 encendidas, 2 apagadas
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < data.streakWeekends ? Color.bpAmber : Color.white.opacity(0.15))
                            .frame(width: 7, height: i < data.streakWeekends ? 22 : 14)
                    }
                }
            }
            Text(data.streakHint)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bpAmber.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .opacity(appearStage >= 4 ? 1 : 0)
        .offset(y: appearStage >= 4 ? 0 : 12)
    }

    // MARK: - Ask (pregunta de precio)

    @ViewBuilder
    private func askCard(data: NightRecapData) -> some View {
        // Sin venue resuelto (sin check-in, o id desconocido) no hay a quién
        // referir la pregunta: la tarjeta no se dibuja.
        if let venueId = data.askVenueId, let venueName = data.askVenueName {
            askCardBody(venueId: venueId, venueName: venueName)
        }
    }

    private func askCardBody(venueId: String, venueName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow. Sin promesa de XP: PointsEngine no tiene una XPAction
            // para reportar precio, así que no se anuncia ninguna.
            Text("Una pregunta")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.white.opacity(0.6))

            Text("¿Cuánto pagaste el trago en \(venueName)?")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            // Pills
            FlowRecapRow(spacing: 7) {
                ForEach(Array(pricePills.enumerated()), id: \.offset) { idx, pill in
                    let isOn = (selectedPricePill == idx)
                    Button {
                        submitPrice(index: idx, cents: pill.cents, venueId: venueId)
                    } label: {
                        Text(pill.label)
                            .font(.system(size: 12, weight: isOn ? .heavy : .semibold,
                                          design: .rounded))
                            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.78))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(
                                Capsule().fill(isOn ? Color.bpAmber : Color.white.opacity(0.07))
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isOn ? Color.bpAmberBright : Color.white.opacity(0.14),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(priceReport == .sending || priceReport == .sent)
                }
            }
            .padding(.top, 10)

            // Footer: sólo cuando hay algo real que decir. El "gracias" existe
            // únicamente después de que el POST volvió bien.
            if let footer = priceFooter {
                HStack(spacing: 6) {
                    Image(systemName: footer.icon)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(footer.tint)
                    Text(footer.text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(footer.tint)
                }
                .padding(.top, 9)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .opacity(appearStage >= 4 ? 1 : 0)
        .offset(y: appearStage >= 4 ? 0 : 12)
    }

    private var priceFooter: (icon: String, text: String, tint: Color)? {
        switch priceReport {
        case .idle, .declined:
            return nil
        case .sending:
            return ("arrow.up.circle", "Enviando tu reporte…", Color.white.opacity(0.55))
        case .sent:
            return ("checkmark.circle.fill", "Gracias — tu reporte ya ayuda al catálogo", Color.bpGreen)
        case .failed:
            return ("exclamationmark.circle", "No se pudo enviar. Toca de nuevo para reintentar.", Color.bpDanger)
        }
    }

    /// Un tap = un POST real a `venue_price_reports`. "no sé" (cents nil)
    /// sólo marca la pill y cierra la pregunta sin escribir nada.
    private func submitPrice(index: Int, cents: Int?, venueId: String) {
        guard priceReport != .sending, priceReport != .sent else { return }
        BPHaptics.light()
        withAnimation(.easeOut(duration: 0.15)) {
            selectedPricePill = index
        }
        guard let cents else {
            withAnimation(.easeOut(duration: 0.15)) { priceReport = .declined }
            return
        }
        priceReport = .sending
        Task {
            do {
                try await store.reportDrinkPrice(venueId: venueId, cents: cents)
                BPHaptics.success()
                withAnimation(.easeOut(duration: 0.2)) { priceReport = .sent }
            } catch {
                BPHaptics.error()
                withAnimation(.easeOut(duration: 0.2)) {
                    priceReport = .failed
                    selectedPricePill = nil
                }
            }
        }
    }

    // MARK: - CTA

    private func ctaButton(data: NightRecapData) -> some View {
        Button {
            onDismiss()
        } label: {
            HStack(spacing: 10) {
                Text(data.fridayCTA)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
            }
            .padding(.vertical, 17).padding(.horizontal, 20)
            .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bpAmberBright, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .opacity(appearStage >= 5 ? 1 : 0)
        .offset(y: appearStage >= 5 ? 0 : 14)
    }

    // MARK: - Share

    private func shareNight() {
        let text = store.shareText.isEmpty
            ? "Mi noche en BarPass"
            : store.shareText
        BPHaptics.selection()
        ShareManager.present(ShareManager.Content(text: text, url: nil, cardImage: nil))
    }

    // MARK: - Entrance

    private func animateIn() {
        guard appearStage == 0 else { return }
        let steps: [(delay: Double, stage: Int)] = [
            (0.00, 1), (0.15, 2), (0.30, 3), (0.50, 4), (0.70, 5),
        ]
        for s in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + s.delay) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    appearStage = s.stage
                }
            }
        }
    }
}

// MARK: - Empty / error states

/// "Nada que recordar de anoche." No inflamos stats falsos: se dice que no
/// hubo salida registrada y se invita a planear la próxima. Mantiene la
/// familia visual (header con eyebrow, tipografía serif italic, CTA amber).
@MainActor
private struct NightRecapEmptyView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 70)

            // Eyebrow
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
                Text("Tu noche de ayer")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 24)

            // Título
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Noche")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
                Text("en pausa")
                    .font(.system(size: 32, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Text("Anoche no te vimos en ningún venue registrado en BarPass. Si saliste y no hiciste check-in, no te la vamos a inventar — este espacio se llena solo cuando hay una noche real para recordar.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)

            // CTA — abrir Remy / plan próximo
            Button(action: { BPHaptics.selection(); onDismiss() }) {
                HStack(spacing: 10) {
                    Text("Armar la próxima noche")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.black)
                }
                .padding(.vertical, 17).padding(.horizontal, 20)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.bpAmberBright, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct NightRecapErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("No pude cargar tu noche")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(4)
            Button(action: { BPHaptics.selection(); onRetry() }) {
                Text("Reintentar")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Background (mañana — más claro que la noche, pero sigue oscuro)

@MainActor
private struct RecapBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.045).ignoresSafeArea()

            // Sol de rayos abstractos — reemplazo del SVG del mockup (los
            // triángulos radiales). Un gradiente cónico con los mismos tonos
            // da la impresión de "amanecer agitado" sin cargar el frame.
            GeometryReader { proxy in
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.96, green: 0.65, blue: 0.14),
                        Color(red: 0.79, green: 0.12, blue: 0.42),
                        Color(red: 0.91, green: 0.64, blue: 0.12),
                        Color(red: 0.84, green: 0.30, blue: 0.12),
                        Color(red: 0.56, green: 0.11, blue: 0.37),
                        Color(red: 0.96, green: 0.65, blue: 0.14),
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.08)
                )
                .frame(width: proxy.size.width * 2.6,
                       height: proxy.size.width * 2.6)
                .position(x: proxy.size.width * 0.5,
                          y: proxy.size.width * -0.3)
                .opacity(0.42)
                .blur(radius: 20)
            }
            .ignoresSafeArea()

            // Vignette cálida — igual que OnboardingV2, mantiene la familia.
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Máscara al negro en la mitad baja, así el contenido respira.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.28),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Grano sutil para unir con el resto de la familia visual.
            RecapGrain(opacity: 0.11)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Helpers de UI

@MainActor
private struct RecapStat: View {
    let big: String
    let small: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(small)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.vertical, 11).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

@MainActor
private struct PolaroidView: View {
    let moment: NightRecapMoment
    let rotation: Double

    var body: some View {
        VStack(spacing: 0) {
            // "Foto" — sin asset real, un degradado del color del momento
            // sobre un pattern tipo film. Cuando venue_media.json tenga la
            // foto, se puede swappear por CachedImage sin tocar el layout.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        moment.tint,
                        moment.tint.opacity(0.55),
                        Color.black.opacity(0.9),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Flashes de luz — simulan la foto de celular con flash.
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.55), .clear],
                        center: .center, startRadius: 2, endRadius: 55
                    ))
                    .frame(width: 90, height: 90)
                    .offset(x: 45, y: -35)
                    .blendMode(.screen)
            }
            .frame(width: 128, height: 128)
            .clipped()

            // Caption (venue · hora, o sólo la hora si el id no resolvió)
            Text(moment.caption)
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 10)
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.88))
        .overlay(
            Rectangle()
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.6), radius: 8, x: 2, y: 8)
        .rotationEffect(.degrees(rotation))
        .padding(.vertical, 6)
    }
}

/// Flow horizontal — pills que envuelven a la siguiente línea cuando ya no
/// caben. SwiftUI no trae uno; es la misma mini-Layout que usa OnboardingV2.
private struct FlowRecapRow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Grano interno — autocontenido para no acoplarnos al GrainTexture del
/// onboarding (ese es `private` a su archivo). Un canvas con puntos semilla
/// fijos para que no parpadee entre redraws.
@MainActor
private struct RecapGrain: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            // 1_600 puntos pseudoaleatorios con semilla fija.
            var seed: UInt64 = 0x4F2A_9E71_8A5B_C13D
            for _ in 0..<1_600 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let rx = Double(seed >> 33) / Double(UInt32.max)
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let ry = Double(seed >> 33) / Double(UInt32.max)
                let x = CGFloat(rx) * size.width
                let y = CGFloat(ry) * size.height
                let rect = CGRect(x: x, y: y, width: 1.0, height: 1.0)
                context.fill(Path(rect), with: .color(Color.white.opacity(0.5)))
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mockup") {
    NightRecapView(data: .mockup)
        .environmentObject(AppState())
        .environmentObject(VenueStore())
}
#endif
