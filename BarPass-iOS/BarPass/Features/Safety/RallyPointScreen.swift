import SwiftUI

/// La pantalla del PUNTO DE ENCUENTRO — "estamos acá" —: un color sólido que
/// ocupa TODA la pantalla, y la mascota en el centro. Cero texto, cero
/// botones, cero menús.
///
/// NO es el faro de auxilio. El auxilio ("estoy acá, vengan") lo enciende la
/// persona en problemas, con su propio color y ritmo (`BeaconBroadcastView`).
/// Esta luz la enciende el LÍDER, para que su gente lo encuentre. Son dos
/// señales distintas y por eso tienen identidades distintas — ver
/// `RallyPointIdentity`, que es el ÚNICO lugar donde se decide cuál es.
///
/// ESTADO E de la máquina "Radar → apretón de manos → punto de encuentro".
/// Sólo se muestra en primer plano, y sólo en el teléfono del LÍDER: cuando
/// tocó el banner "Juan está a menos de 9 m" y el servidor confirmó que es el
/// objetivo de la búsqueda — ver `SafetyPushRouter.lightRallyPoint()`. Un
/// buscador nunca llega acá.
/// Al aparecer toma pantalla al 100% + linterna por `BeaconFlares`, que es el
/// único dueño del hardware; al desaparecer la suelta.
///
/// CÓMO SE SALE sin un solo botón visible: mantener apretado 1,2 s en
/// cualquier parte. Es a propósito un gesto largo — un toque suelto en un
/// bar oscuro, con la pantalla en alto sobre la cabeza, no debe apagar la
/// señal. Además se apaga sola cuando vence la búsqueda o el tope de sesión
/// de `BeaconFlares`, y VoiceOver tiene una acción con nombre.
///
/// El color NO parpadea: el ritmo lo lleva la linterna. Una pantalla entera
/// de color pleno destellando frente a desconocidos es justo el riesgo
/// fotosensible que `FlarePattern` acota; acá el color es el que identifica
/// y la linterna es la que pulsa.
struct RallyPointScreen: View {
    let request: SafetyPushRouter.RallyPointRequest
    let onClose: () -> Void

    @ObservedObject private var flares = BeaconFlares.shared
    @ObservedObject private var l10n = L10n.shared

    /// Cuánto hay que mantener apretado para apagarlo. Es un seguro contra toques
    /// sueltos en un bar oscuro: no bajarlo de ~1 s.
    static let holdSeconds: Double = 1.2

    var body: some View {
        ZStack {
            RallyPointIdentity.color
                .ignoresSafeArea()
            Image("BarPassMascot")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: RallyPointIdentity.mascotMaxSize, maxHeight: RallyPointIdentity.mascotMaxSize)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Self.holdSeconds) { onClose() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t("safetyGroup.rally.a11y"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: l10n.t("safetyGroup.rally.close")) { onClose() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            // La luz del PUNTO DE ENCUENTRO tiene dueño `.rally`: el poll del faro
            // propio (`SafetyBeaconStore`) sólo apaga lo que es `.mine`, así que no
            // puede apagar esta, y nadie tiene que consultar el estado de otro store.
            flares.start(pattern: RallyPointIdentity.flarePattern,
                         anchoredAt: request.startedAt, owner: .rally)
            let remaining = request.expiresAt.timeIntervalSinceNow
            guard remaining > 0 else { onClose(); return }
            try? await Task.sleep(for: .seconds(remaining))
            if !Task.isCancelled { onClose() }
        }
        .onChange(of: flares.state) { _, state in
            // El tope de sesión se cumplió: sólo el usuario lo renueva, y
            // esta pantalla no tiene con qué. Se cierra.
            if state == .expired { onClose() }
        }
        .onDisappear { flares.stop(by: .rally) }
    }
}
