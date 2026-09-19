import SwiftUI

/// La única superficie de dibujo del radar. Recibe UN estado y dibuja ESE
/// estado: no hay una figura genérica de "algo está pasando" que sirva para
/// varios, porque ahí es donde una pantalla empieza a mentir — un anillo que
/// gira igual mientras busca señal que mientras la perdió le dice a la persona
/// que todo sigue bien cuando no sigue.
///
/// Reglas que este archivo sostiene:
///  · La flecha se dibuja SÓLO en `.directed`. Es el único estado que tiene un
///    vector; cualquier otro con flecha estaría dibujando un invento.
///  · `heading.isConfirmed == false` no es un matiz: ese vector puede tener
///    0,6 s de atraso y estar hasta ~110° equivocado si la persona giró. Acá
///    baja a opacidad 0,32, pierde el color ámbar, pierde el halo encendido y
///    el anillo pasa a punteado. Se tiene que notar de reojo.
///  · `.signalLost` NO congela la última flecha. Anillo cortado y antena
///    tachada: se perdió, y la pantalla lo dice.
///  · `.paused`, `.peerLeft` y `.signalLost` terminan los tres sin medición,
///    y los tres se dibujan distinto: se fue la app, se fue la persona, se fue
///    la radio. Colapsarlos en una figura gris común haría que la pantalla
///    conteste "no hay señal" a tres preguntas con tres respuestas.
///  · Reduce Motion apaga todo lo que late. Lo que queda es la misma
///    información, quieta — nunca menos información.
///
/// No habla con VoiceOver a propósito: la pantalla describe el conjunto en una
/// sola frase (`radar.accessibility.arrow`), y un dial que además hablara leería
/// el mismo hecho dos veces.
struct ProximityRadarDial: View {
    let state: ProximityRadarState
    var diameter: CGFloat = 250

    /// Distancia más lejana que el anillo de alcance mapea. Más allá se pega al
    /// borde: el anillo dice "están en algún lugar de este radio", y estirar la
    /// escala para que 80 m entren daría un anillo que casi no se mueve en los
    /// 10 m donde la persona de verdad camina.
    private static let maxMappedMeters: Double = 30

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.bpBorder, lineWidth: 1)
            Circle()
                .strokeBorder(Color.bpBorder, lineWidth: 1)
                .frame(width: diameter * 0.58, height: diameter * 0.58)
            // Vos. El centro siempre está, en todos los estados: es lo único
            // que el radar sabe con certeza.
            Circle().fill(Color.bpTextTertiary).frame(width: 7, height: 7)
            content
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .directed(_, let heading):
            NeedleView(azimuth: heading.azimuth,
                       isConfirmed: heading.isConfirmed,
                       diameter: diameter)
        case .holdPhoneFlat:
            FlatPhoneHint(diameter: diameter)
        case .distanceOnly(let meters, _):
            rangeRing(meters)
        case .acquiring, .waitingForPeer:
            SearchPulse(diameter: diameter)
        case .signalLost:
            lostRing
        case .paused:
            // Detenido, no roto: iOS apaga NearbyInteraction cuando la app se
            // va al fondo. El anillo queda entero — no se perdió nada — con la
            // pausa adentro, que es lo único que pasó.
            mark("pause.fill", ringDash: [], tint: Color.bpTextSecondary)
        case .peerLeft:
            // Se fue la persona, no la señal. Distinto de `.signalLost`, donde
            // los dos siguen ahí y lo que falló fue la radio entre medio.
            mark("person.fill.xmark", ringDash: [2, 9], tint: Color.bpTextSecondary)
        case .idle:
            // El único estado sin figura, y con razón: el radar todavía no
            // arrancó, así que no hay nada midiéndose que dibujar. Dura el
            // frame que va entre montar la vista y su `.onAppear`.
            EmptyView()
        case .unsupported, .permissionDenied, .peerCannotRange, .arrived, .failed:
            // `shouldFallBackToBeacon`: la pantalla ni siquiera muestra el dial
            // en estos: el color pasa a ser el protagonista.
            EmptyView()
        }
    }

    /// Un glifo adentro del anillo grande. Cada estado elige su figura y si el
    /// anillo está entero o cortado — el corte significa que se rompió algo,
    /// así que no se reparte de adorno.
    private func mark(_ symbol: String, ringDash: [CGFloat], tint: Color) -> some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.45),
                              style: StrokeStyle(lineWidth: 2, dash: ringDash))
                .frame(width: diameter * 0.86, height: diameter * 0.86)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.18, weight: .light))
                .foregroundStyle(tint)
        }
    }

    // MARK: - Alcance sin dirección

    /// Sin flecha no hay "para allá", pero sí hay "a este radio". El anillo es
    /// literalmente eso: el lugar geométrico donde puede estar la persona. Es
    /// la figura honesta para `.distanceOnly` y además hace visible el
    /// acercarse — el anillo se cierra sobre el centro sin que nadie tenga que
    /// leer el número.
    private func rangeRing(_ meters: Double) -> some View {
        // Raíz cuadrada, no lineal: comprime los metros lejanos y le deja
        // resolución a los primeros 10 m, que son los que se caminan mirando
        // la pantalla.
        let clamped = min(max(meters, 0), Self.maxMappedMeters)
        let ratio = (clamped / Self.maxMappedMeters).squareRoot()
        let size = diameter * (0.22 + 0.76 * ratio)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.bpAmber.opacity(0.16), .clear],
                                     center: .center, startRadius: 0, endRadius: size / 2))
            Circle().strokeBorder(Color.bpAmber.opacity(0.85), lineWidth: 2.5)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.45), value: size)
    }

    // MARK: - Señal perdida

    /// Anillo cortado, gris, antena tachada. Deliberadamente NO es la flecha
    /// anterior en gris: una flecha quieta sigue apuntando a algún lado, y la
    /// persona la sigue.
    private var lostRing: some View {
        mark("antenna.radiowaves.left.and.right.slash",
             ringDash: [3, 10], tint: Color.bpTextSecondary)
    }
}

// MARK: - La flecha

private struct NeedleView: View {
    let azimuth: Double
    let isConfirmed: Bool
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ángulo acumulado, NO el azimut crudo. `rotationEffect` interpola por el
    /// número, así que cruzar de +179° a -179° —alguien que gira y deja a su
    /// amigo justo atrás— haría girar la aguja 358° por el lado largo. Acá se
    /// suma siempre el delta corto, así que la aguja hace 2°.
    @State private var unwrapped: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isConfirmed ? Color.bpAmber.opacity(0.5) : Color.bpTextSecondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isConfirmed ? 2 : 1.5,
                                       dash: isConfirmed ? [] : [5, 8])
                )
                .frame(width: diameter * 0.86, height: diameter * 0.86)

            Image(systemName: "location.north.fill")
                .font(.system(size: diameter * 0.30, weight: .black))
                .foregroundStyle(isConfirmed ? Color.bpAmber : Color.bpTextSecondary)
                .opacity(isConfirmed ? 1 : 0.32)
                .shadow(color: isConfirmed ? Color.bpAmber.opacity(0.45) : .clear, radius: 18)
                .rotationEffect(.radians(unwrapped))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: unwrapped)
        }
        .onAppear { unwrapped = azimuth }
        .onChange(of: azimuth) { _, new in advance(to: new) }
    }

    private func advance(to new: Double) {
        var delta = (new - unwrapped).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        unwrapped += delta
    }
}

// MARK: - Cómo se sostiene el teléfono

/// El azimut es un ángulo en el plano de la PANTALLA: se lee como un mapa con
/// el teléfono horizontal y se sesga a medida que se inclina. Así que este
/// estado no dice "no se puede": muestra el movimiento que hay que hacer.
private struct FlatPhoneHint: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlat = false

    var body: some View {
        Image(systemName: "iphone")
            .font(.system(size: diameter * 0.34, weight: .light))
            .foregroundStyle(Color.bpAmber)
            .rotationEffect(.degrees(reduceMotion || isFlat ? -90 : 0))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                       value: isFlat)
            .onAppear { isFlat = true }
    }
}

// MARK: - Buscando

/// Un pulso que sale del centro, no un spinner. Un spinner dice "esperá" sin
/// decir qué; esto dice "estamos escuchando alrededor tuyo", que es lo que
/// literalmente está pasando mientras llega la primera medición.
private struct SearchPulse: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Group {
            if reduceMotion {
                // Sin movimiento queda el mismo hecho, quieto: hay un radio de
                // escucha y todavía no hay nada adentro.
                Circle()
                    .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 2)
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            } else {
                Circle()
                    .strokeBorder(Color.bpAmber.opacity(expanded ? 0 : 0.55), lineWidth: 2)
                    .frame(width: diameter * (expanded ? 0.95 : 0.18),
                           height: diameter * (expanded ? 0.95 : 0.18))
                    .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false),
                               value: expanded)
                    .onAppear { expanded = true }
            }
        }
    }
}
