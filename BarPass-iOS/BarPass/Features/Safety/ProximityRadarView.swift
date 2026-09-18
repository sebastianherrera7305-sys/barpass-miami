import SwiftUI

/// Búsqueda precisa entre dos personas: la flecha y la distancia, y el color
/// cuando la flecha no existe.
///
/// La pantalla no decide NADA sobre la medición — eso ya está resuelto en
/// `ProximityRadar` / `ProximityRadarCore`, donde cada estado tiene un
/// significado escrito y una sola frase (`state.messageKey`). Acá sólo se
/// dibuja lo que ese estado dice, con tres reglas que no se negocian:
///
///  1. Un estado por vez, dibujado como lo que es. Ninguno se disfraza de otro.
///  2. `heading.isConfirmed == false` se atenúa a la vista Y se dice en voz
///     alta para VoiceOver: atenuar sólo el píxel dejaría la mentira intacta
///     para quien no ve la pantalla.
///  3. `state.shouldFallBackToBeacon` lleva al color como protagonista, sin
///     culpa. Un iPhone SE no tiene antena de precisión; eso no es un error de
///     quien lo compró, y el color funciona igual en los dos teléfonos.
///
/// Presentala en sheet, como `TripDetailView`: trae su propio `NavigationStack`.
/// Cuando el beacon es tuyo, `peerUserId`/`peerName` son de quien viene a
/// buscarte — una sesión de NearbyInteraction es 1 a 1.
struct ProximityRadarView: View {
    let beacon: SafetyBeacon
    let peerUserId: String
    let peerName: String

    @ObservedObject private var l10n = L10n.shared
    /// SOBRE LA ESCALA. Esta pantalla NO abre un poll propio para saber si el
    /// beacon sigue vivo: lee el store que el grupo ya está mirando. Un bar
    /// lleno con veinte búsquedas abiertas cuesta veinte canales de tokens,
    /// que es el mínimo irreducible; sumarle veinte polls de estado sería
    /// duplicar el tráfico para repetir una respuesta que ya llegó.
    @ObservedObject private var store = SafetyBeaconStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Reintentar no es volver a llamar a `start()`: el canal de tokens se
    /// cierra para siempre en `stop()` (y sólo al cerrarse deja de pollear al
    /// backend cada 3 s). Un reintento necesita un canal nuevo, así que cambia
    /// la identidad de la sesión y SwiftUI construye un `ProximityRadar` nuevo.
    @State private var attempt = 0
    @State private var isExpired = false

    /// La fila viva, si el store la tiene. El parámetro `beacon` es el valor
    /// con el que se abrió la pantalla y envejece; `isResolved` cambia del otro
    /// lado del salón. Si el store todavía no contestó nada, el valor de
    /// entrada es la mejor respuesta que hay — nunca una pantalla vacía.
    private var live: SafetyBeacon { store.beacons.first { $0.id == beacon.id } ?? beacon }

    /// Se terminó la búsqueda: o la encontraron, o el beacon venció y el
    /// servidor ya borró su fila. Importa que lo decida la pantalla y no el
    /// canal: cuando el canal se entera, traduce la fila faltante a `.peerLeft`
    /// — "cerró la app" — que en estos dos casos es falso.
    private var isOver: Bool { live.isResolved || isExpired }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BPSpacing.lg) {
                        header
                        if isOver {
                            // Sacar la sesión del árbol dispara su `.onDisappear`,
                            // que es lo que apaga la NISession y cierra el canal.
                            // Una búsqueda terminada deja de costarle al backend
                            // en el acto, no en el próximo poll.
                            closed
                        } else {
                            ProximityRadarSession(beacon: live,
                                                  peerUserId: peerUserId,
                                                  onRetry: { attempt += 1 })
                                .id(attempt)
                            footer
                        }
                    }
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.top, BPSpacing.md)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle(l10n.t("radar.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }
                        .foregroundStyle(Color.bpAmber)
                        .bpAccessibility(label: l10n.t("table.close"), isButton: true)
                }
            }
            .task(id: live.expiresAt) { await waitForExpiry(at: live.expiresAt) }
        }
    }

    /// Un solo sleep hasta el instante exacto del vencimiento, en vez de un
    /// reloj que pregunte "¿ya?" una vez por segundo durante veinte minutos.
    /// `try?` se traga la cancelación, así que el guard es lo que evita marcar
    /// vencido un beacon que simplemente se fue de pantalla.
    private func waitForExpiry(at date: Date) async {
        isExpired = false
        let wait = date.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled else { return }
        isExpired = true
    }

    private var header: some View {
        VStack(spacing: BPSpacing.xs) {
            Text(peerName)
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            // `placeIsKnown == false` no es "en ningún lado": es que no lo
            // sabemos, y la clave lo dice con esas palabras.
            Text(live.venueName ?? l10n.t("safety.place.unknown"))
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
            if let note = live.note, !note.isEmpty {
                Text(note)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, BPSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .bpEntrance(offset: CGSize(width: 0, height: 8))
    }

    /// Dos finales distintos, dichos distinto. "La encontraron" es una buena
    /// noticia; "el beacon venció" es que el servidor ya no tiene nada que
    /// entregar — y en ninguno de los dos casos queda algo que medir.
    private var closed: some View {
        VStack(spacing: BPSpacing.sm) {
            Image(systemName: live.isResolved ? "checkmark.circle.fill" : "hourglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(live.isResolved ? Color.bpGreen : Color.bpTextSecondary)
            Text(l10n.t(live.isResolved ? "safety.beacon.found" : "safety.error.notFound"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
        }
        .padding(BPSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpEntrance(offset: CGSize(width: 0, height: 10), delay: 0.05)
    }

    /// Un beacon vive 20 minutos y después borra su propia fila. Decir cuánto
    /// queda es la diferencia entre una pantalla que se apaga sola sin aviso y
    /// una que avisó.
    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, live.expiresAt.timeIntervalSince(context.date))
            Text(String(format: l10n.t("safety.beacon.expiresIn"), RadarText.age(left)))
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextTertiary)
        }
    }
}

// MARK: - Texto

/// Formateo del radar, en un solo lugar y con formateadores cacheados: asignar
/// un `NumberFormatter` por llamada en el hilo principal es lo que congeló el
/// feed de Tonight una vez (ver `VenueTimeStatus`), y acá el número se redibuja
/// a ~10 Hz mientras alguien camina.
@MainActor
enum RadarText {
    /// Metros en las tres lenguas de la app. Sin conversión a pies: una sola
    /// unidad mantiene un solo argumento de precisión, y la precisión es el
    /// punto de toda esta pantalla.
    static let unit = "m"

    /// Arriba de acá la lectura ya no viene del régimen preciso sino del
    /// extendido, que existe justamente porque el otro no llega tan lejos.
    /// También es donde el anillo del dial se pega al borde y deja de resolver
    /// posición: el número queda solo, así que tiene que decir su propio error.
    private static let coarseAbove: Double = 30

    static func distance(_ meters: Double, language: AppLanguage) -> String {
        number(meters, language: language) + " " + unit
    }

    /// CUÁNTOS DECIMALES — tres bandas, una por régimen de medición.
    ///
    /// · Menos de 10 m: un decimal. UWB mide con ~±10 cm y el filtro del motor
    ///   (tau 0,4 s) agrega medio metro de atraso a paso de caminata, así que
    ///   el dígito de los décimos YA es el incierto, que es exactamente lo que
    ///   el último dígito mostrado tiene que ser. Un segundo decimal sería
    ///   inventar centímetros.
    /// · 10 a 30 m: metros enteros. Un décimo ahí es ruido del filtro.
    /// · Más de 30 m: al múltiplo de 5 más cercano y con "≈". Apple no publica
    ///   el error del modo extendido; lo que sí está escrito es que cambia
    ///   precisión por alcance. Un "47 m" al metro promete una exactitud que
    ///   nadie afirmó — y un número redondo con el signo adelante dice la
    ///   verdad completa: hay distancia, no hay metro exacto.
    static func number(_ meters: Double, language: AppLanguage) -> String {
        if meters > coarseAbove {
            return "≈" + format((meters / 5).rounded() * 5, digits: 0, language: language)
        }
        return format(meters, digits: meters < 10 ? 1 : 0, language: language)
    }

    /// "12 s" / "3 min". Sin claves nuevas a propósito: las tres lenguas
    /// abrevian igual, y un formateador relativo diría "hace 12 segundos"
    /// encima del "hace" que ya trae `radar.signalLost.age`.
    static func age(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total < 60 ? "\(total) s" : "\(total / 60) min"
    }

    /// El azimut, dicho como lo diría una persona. 0 rad sale por el borde
    /// superior de la pantalla = las 12; positivo va hacia la derecha.
    static func clockHour(_ azimuth: Double) -> Int {
        let step = 2 * Double.pi / 12
        let raw = Int((azimuth / step).rounded())
        let hour = ((raw % 12) + 12) % 12
        return hour == 0 ? 12 : hour
    }

    /// Las claves `radar.*` llevan marcadores `{0}` (las `safety.*` usan `%@`).
    /// Vive acá y no en una extensión de `String` para no plantar un nombre
    /// genérico en todo el target por una convención de una sola pantalla.
    static func fill(_ text: String, _ values: String...) -> String {
        var out = text
        for (index, value) in values.enumerated() {
            out = out.replacingOccurrences(of: "{\(index)}", with: value)
        }
        return out
    }

    private static func format(_ meters: Double, digits: Int, language: AppLanguage) -> String {
        let formatter = cached(digits: digits, language: language)
        return formatter.string(from: NSNumber(value: meters)) ?? String(Int(meters.rounded()))
    }

    private static func cached(digits: Int, language: AppLanguage) -> NumberFormatter {
        let key = "\(digits)|\(language.rawValue)"
        if let hit = formatters[key] { return hit }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatters[key] = formatter
        return formatter
    }

    private static var formatters: [String: NumberFormatter] = [:]
}
