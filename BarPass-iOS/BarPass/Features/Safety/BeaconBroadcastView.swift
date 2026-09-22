import SwiftUI

// LA BALIZA. Esta pantalla no MUESTRA la señal: ES la señal. Alguien la va a
// levantar por encima de la cabeza en un lugar oscuro y lleno de gente, y del
// otro lado del salón lo único que llega es un color y un ritmo.
//
// Cuatro decisiones cargan con casi todo:
//
// 1. EL RELOJ NO ES NUESTRO. El encendido sale de
//    `rhythm.isLit(atSecondsSinceStart:)` medido contra `BeaconFlares.anchor`
//    — el mismo instante del que se deriva la linterna. Un reloj propio
//    parece equivalente y no lo es: los timers garantizan "al menos" N ms, el
//    error se acumula, y a los dos minutos la pantalla va media fase corrida
//    respecto del haz. De lejos eso no es un detalle estético: son dos
//    señales distintas saliendo del mismo teléfono, y ninguna es de nadie.
//
// 2. EL TEXTO NO VIVE ENCIMA DEL COLOR. "Sos el DORADO, destello rápido" es
//    el respaldo de todo lo que el color no sostiene: un dicrómata, una luz
//    de sala que corrompe el tono, un grito de una punta a la otra. Encima
//    del campo que parpadea sería ilegible justo la mitad del tiempo, así que
//    vive en una placa NEGRA OPACA que nunca late. Por lo mismo se esconden
//    la barra de navegación y el reloj: es texto del sistema sobre el destello.
//
// 3. LA SEÑAL NO ES DE ESTA PANTALLA. La sostiene `SafetyBeaconStore`, que la
//    enciende mientras exista la fila del beacon y la apaga cuando se resuelve
//    o vence, aunque nadie esté mirando. Salir de acá no apaga nada —y el
//    botón lo dice con todas las letras— porque lo único que apaga la baliza
//    es RESOLVER el beacon: apagarla en silencio deja a tres personas
//    buscando a alguien que ya apareció.
//
// 4. NO SOS EL ÚNICO EN EL BAR. Con varios grupos adentro el color solo deja
//    de alcanzar; la señal es color Y ritmo. Cuando vemos otro beacon vivo del
//    mismo color lo decimos, en vez de dejar que dos personas en dorado se
//    repartan la misma gente. Ver `sharedColorName`.
//
// La placa ignora el tema claro a propósito: `Color.bpInk` se da vuelta con
// `AppearanceStore.isDark` y sería tinta oscura sobre negro. Acá la pantalla
// es la fuente de luz, no una hoja. Del design system salen tipografía,
// espaciado y háptica; el blanco y el negro son explícitos.

struct BeaconBroadcastView: View {
    let beacon: SafetyBeacon

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyBeaconStore.shared
    @ObservedObject private var flares = BeaconFlares.shared
    @Environment(\.dismiss) private var dismiss
    /// El ajuste de iOS que de verdad habla de esto ("Atenuar luces
    /// intermitentes"). NO "Reducir movimiento": ver `darkFloor`.
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashing

    /// Espejo del ancla del servicio, sólo para ARMAR el schedule — que es un
    /// valor `Sendable` y no puede leer un singleton `@MainActor`. La verdad
    /// del encendido se sigue leyendo de `flares.anchor` en cada frame, así
    /// que un espejo viejo desafina el redibujo, nunca la fase.
    @State private var anchor = Date()
    @State private var sawLive = false
    @State private var isEnding = false
    @State private var endError: String?

    /// La fila viva del store; el parámetro es la foto de cuando se abrió.
    private var live: SafetyBeacon { store.beacons.first { $0.id == beacon.id } ?? beacon }
    private var signal: BeaconSignal { store.signal(for: beacon) }

    /// La línea que se puede GRITAR, armada por l10n en un solo string.
    private var identitySentence: String {
        String(format: l10n.t("safety.beacon.youAre"),
               l10n.t(signal.colorNameKey), l10n.t(signal.rhythmNameKey))
    }

    /// La fase oscura NO es negro puro. En negro puro el teléfono deja de
    /// emitir entre destellos: quien mira justo ahí no ve nada, ni siquiera
    /// dónde está el teléfono en alto, y el rectángulo desaparece. Con el 12%
    /// del mismo tono queda una brasa que sostiene la silueta y todavía dice
    /// de qué color sos, a ~1/66 de la luminancia del destello — contraste de
    /// sobra para que el destello siga leyéndose como destello.
    ///
    /// Con "Atenuar luces intermitentes" el piso sube a 0,55 (≈4:1): el ritmo
    /// se sigue distinguiendo, el golpe de luz no. "Reducir movimiento", en
    /// cambio, NO apaga el parpadeo: el ritmo ES la mitad de la identidad
    /// —para un dicrómata, la única que sobrevive— y apagarlo pondría a dos
    /// personas en la misma señal. Ese ajuste existe contra el movimiento
    /// decorativo, y acá no hay ninguno que apagar.
    private var darkFloor: Double { dimFlashing ? 0.55 : 0.12 }

    private var isBroadcasting: Bool {
        if case .active = flares.state { return true }
        return false
    }

    /// MUCHOS A LA VEZ. Cuatro colores alcanzan para separarte de tu grupo, no
    /// del salón: con varios beacons simultáneos dos personas pueden estar en
    /// dorado y el color deja de identificar a nadie. Esto mira los beacons
    /// que este teléfono YA tiene del poll —no pide nada más a la red, que en
    /// un lugar lleno es justo lo que no sobra— y avisa cuando otro comparte
    /// el color. Sólo ve los beacons dirigidos a mí: dos desconocidos en
    /// dorado siguen siendo invisibles, y por eso el ritmo va en la frase
    /// principal y no acá.
    private var sharedColorName: String? {
        let clash = store.incoming.contains {
            !$0.isResolved && store.signal(for: $0).identity == signal.identity
        }
        return clash ? l10n.t(signal.colorNameKey) : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            flashField
            // Con Dynamic Type grande la placa no entra: ahí, y sólo ahí,
            // scrollea. Cuando hay que elegir, gana el texto.
            ViewThatFits(in: .vertical) { plate; ScrollView { plate } }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Sin botón de volver también se apaga el gesto de arrastrar desde el
        // borde. Es deliberado: el teléfono está en alto y el pulgar apoyado
        // en el canto izquierdo. Salir sigue estando a un toque, abajo.
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: appeared)
        .onChange(of: flares.state) { _, state in flareStateChanged(state) }
        .onChange(of: store.beacons) { _, rows in beaconsChanged(rows) }
    }

    // MARK: El campo que parpadea

    private var flashField: some View {
        TimelineView(BeaconPhaseSchedule(rhythm: signal.rhythm, anchor: anchor)) { context in
            let lit = isBroadcasting
                && signal.rhythm.isLit(atSecondsSinceStart: context.date.timeIntervalSince(flares.anchor))
            signal.color.color
                .opacity(lit ? 1 : darkFloor)
                // Corte duro. Interpolar entre fases redondea el borde del
                // destello, que es justo lo que lo hace legible de lejos.
                .animation(nil, value: lit)
        }
        .ignoresSafeArea()
        // Es luz, no un control: nada que tocar donde la mano va a rozar.
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(BeaconFlareCopy.voiceOverSummary(flares.state, identity: identitySentence, l10n))
    }

    // MARK: La placa

    private var plate: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            BeaconIdentityBlock(sentence: identitySentence, tint: signal.color.color)
            if let sharedColorName {
                BeaconStatusRow(line: .init("person.2.fill",
                                            String(format: l10n.t("beacon.broadcast.sameColorNearby"),
                                                   sharedColorName), .bpAmber))
            }
            if isBroadcasting {
                BeaconFlareStatusList(state: flares.state,
                                      patternWasAltered: signal.rhythm.flarePatternWasAltered,
                                      dimFlashing: dimFlashing)
                BeaconAckRow(beacon: live)
                BeaconSessionFooter(beacon: live) { BeaconRenewButton(action: renew) }
            } else {
                // `.expired` y `.pausedOutsideForeground` son estados con
                // nombre y con salida, no pantallas girando. `.idle` no llega
                // acá: `flareStateChanged` lo resuelve encendiendo la baliza,
                // que es la respuesta, no la frase.
                BeaconInterruptedBlock(state: flares.state) { BeaconRenewButton(action: renew) }
            }
            controls
        }
        .padding(BPSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: BPRadius.xxl, topTrailingRadius: BPRadius.xxl)
                // OPACA, no translúcida: con un 6% del campo filtrándose, el
                // texto latiría con el destello.
                .fill(Color.black)
                .overlay(alignment: .top) {
                    Rectangle().fill(signal.color.color.opacity(0.55)).frame(height: 2)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Salir

    private var controls: some View {
        VStack(spacing: BPSpacing.sm) {
            if let endError {
                // El servidor sigue creyendo que estás perdido. Decirlo y
                // dejar el botón vivo es más honesto que cerrar la pantalla.
                Text(endError)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Apagar la baliza es RESOLVER el beacon: es lo único que la deja
            // apagada — mientras la fila siga viva, el store la vuelve a
            // encender en su próximo tick. Por eso el botón dice "me
            // encontraron" y no "apagar": avisa, no sólo apaga.
            HoldToEndButton(
                title: l10n.t("safety.beacon.resolve"),
                caption: l10n.t("beacon.broadcast.endHold"),
                hint: l10n.t("beacon.broadcast.endHint"),
                isBusy: isEnding,
                action: endSignal
            )
            // Un roce acá sólo cierra la pantalla: la señal sigue (la sostiene
            // el servicio, no esta vista) y el botón lo dice. Lo destructivo
            // pide un segundo de presión; lo reversible, un toque. Es además
            // la salida cuando resolver falla, así que nadie queda encerrado.
            Button { BPHaptics.light(); dismiss() } label: {
                Text(l10n.t("beacon.broadcast.keepRunning"))
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("beacon.broadcast.keepRunning"), isButton: true)
        }
    }

    private func endSignal() {
        guard !isEnding else { return }
        isEnding = true
        endError = nil
        BPHaptics.success()
        Task {
            do {
                try await RepositoryDependencies.safetyBeacon.resolve(beaconId: beacon.id)
                // Sin esperar al poll: el store llega a lo mismo, hasta 30 s
                // después, y para entonces esta pantalla ya no existe.
                flares.stop(by: .mine)
                store.refreshNow()
                dismiss()
            } catch {
                isEnding = false
                endError = (error as? LocalizedError)?.errorDescription ?? l10n.t("safety.error.generic")
                BPHaptics.error()
            }
        }
    }

    // MARK: Ciclo de vida

    /// Renovar desde `.expired` NO puede ser `renew()`: ese camino vuelve a
    /// arrancar el servicio con el ancla en AHORA, y los chips de quienes te
    /// buscan laten anclados al nacimiento del beacon — quedarían en
    /// contrafase con el teléfono que de verdad emite. `start(anchoredAt:)`
    /// reancla al mismo origen y, viniendo de `.expired`, reinicia el tope de
    /// sesión igual que `renew()`. Desde cualquier otro estado el ancla ya
    /// está bien y lo único que falta son los diez minutos.
    private func renew() {
        BPHaptics.medium()
        if flares.state == .expired {
            flares.start(pattern: signal.rhythm.flarePattern, anchoredAt: live.createdAt, renewing: true)
        } else {
            flares.renew()
        }
        anchor = flares.anchor
    }

    private func appeared() {
        sawLive = store.beacons.contains { $0.id == beacon.id }
        // Enciende la baliza si hace falta y deja el espejo del ancla al día.
        flareStateChanged(flares.state)
    }

    /// `.idle` con un beacon vivo es el único hueco posible: el store lo
    /// cerraría en su próximo tick, pero eso son hasta cuatro segundos de una
    /// pantalla que dice ser una señal sin serlo. Encenderla acá es
    /// idempotente y usa el MISMO ancla que el store, así que no desfasa nada.
    private func flareStateChanged(_ state: BeaconFlareState) {
        if state == .idle, !isEnding, !live.isResolved {
            flares.start(pattern: signal.rhythm.flarePattern, anchoredAt: live.createdAt)
        }
        anchor = flares.anchor
    }

    private func beaconsChanged(_ rows: [SafetyBeacon]) {
        let match = rows.first { $0.id == beacon.id }
        if match != nil { sawLive = true }
        // Resuelto o vencido: el store apaga la baliza por su cuenta, acá sólo
        // dejamos de ocupar la pantalla con una señal que ya no existe.
        // `sawLive` evita cerrar antes de la primera respuesta del servidor.
        guard sawLive, match?.isResolved ?? true else { return }
        dismiss()
    }
}
