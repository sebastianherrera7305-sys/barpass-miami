import Foundation

// QUÉ PASA CUANDO NO HAY UNA MANO LEVANTADA SINO DOCE.
//
// Todo lo de acá es lógica de valores pura: sin estado, sin red, sin
// callbacks. Mismo criterio que BeaconIdentity.swift y por la misma razón —
// nada de esto puede entrarse desde una cola de fondo— y con un beneficio
// extra: el caso feo (doce beacons, dos con la misma señal, la mitad ya
// respondidos) se puede mirar sin tener que reproducirlo contra el servidor.
//
// Tres problemas aparecen recién con mucha gente a la vez, y ninguna pieza
// del motor los puede resolver porque ninguna ve la lista entera:
//
//  1. COLISIÓN DE SEÑAL. El faro son 4 colores × 4 rotaciones de ritmo, y
//     `BeaconSignal.derived(fromBeaconId:)` lo dice sin vueltas: dos beacons
//     simultáneos pueden caer en el mismo color Y el mismo ritmo. Con una
//     mano levantada es imposible; con cinco deja de ser raro. Esta pantalla
//     es el único lugar de la app que tiene las dos filas juntas y puede
//     DETECTARLO. Si no lo dice, alguien cruza el salón con total confianza
//     hacia la persona equivocada — que es peor que no haber mostrado nada.
//  2. ORDEN. Doce tarjetas en orden de llegada son doce tarjetas para leer
//     una por una. El orden contesta "¿a quién mirás primero?", no "¿qué
//     pasó último?".
//  3. COSTO DE DIBUJO. Cada muestra animada es un TimelineView a ~11 Hz.
//     Cuatro salen gratis; treinta son ~330 evaluaciones de vista por segundo
//     en el único momento de la noche en que el teléfono no puede trabarse.
//     El nombre escrito del color y del ritmo va SIEMPRE, así que capar la
//     animación no esconde ningún dato: saca un adorno.

// MARK: - Audiencia

/// A quién apunta el beacon. `tripId == nil` = "los amigos que están en este
/// lugar", que es el caso sin plan armado (la mayoría de las noches).
struct BeaconAudienceOption: Identifiable, Equatable {
    let tripId: String?
    let title: String
    var id: String { tripId ?? "__here__" }
}

/// Lo que el preflight sabe. `failed` existe aparte de `loaded(names: [])` a
/// propósito: "no pudimos preguntar" y "preguntamos y no hay nadie" son
/// hechos distintos, y colapsarlos en un cartel rojo asusta de gratis.
enum BeaconAudienceState: Equatable {
    case loading
    case failed
    case loaded(names: [String], rosterTotal: Int?)
}

// MARK: - Feed

/// Una fila del feed: el beacon más lo que sólo se sabe mirando a los otros.
struct BeaconFeedEntry: Identifiable, Equatable {
    let beacon: SafetyBeacon
    let signal: BeaconSignal
    /// Otro beacon VIVO de esta misma lista tiene el mismo color y el mismo
    /// ritmo ahora mismo. No es un error del servidor: es el techo de cuatro
    /// colores, dicho a tiempo.
    let signalIsAmbiguous: Bool
    /// Mismo COLOR que otro faro vivo, distinto ritmo. Es un aviso más débil
    /// que el de arriba y aun así hace falta: en un salón oscuro el color es
    /// lo primero que se ve y el ritmo es el desempate. Y hay un par donde
    /// el desempate llega tarde — `fastFlicker` y `doubleBlink` son la MISMA
    /// onda durante sus primeros 720 ms, así que un vistazo entre dos
    /// cuerpos que cruzan no los separa. Ese par convive de verdad: el
    /// servidor reparte gold/fastFlicker en su primer slot y gold/doubleBlink
    /// en el quinto (safety_beacon.sql, tabla de preferencia), o sea que con
    /// cinco manos levantadas en el mismo bar hay dos personas en dorado.
    let colorIsShared: Bool
    /// Falso NO significa "no tiene ritmo": el ritmo sigue escrito al lado
    /// del punto. Significa que este punto no late para ahorrar cuadros.
    let animatesSwatch: Bool
    /// Incluye el acuse optimista: el RPC ya devolvió 200 y el poll todavía
    /// no trajo la fila nueva. Mueve el botón, nunca el orden — ver `priority`.
    let iAmOnMyWay: Bool

    var id: String { beacon.id }
}

enum BeaconFeed {
    /// Cuatro: las que entran en una pantalla. Más arriba de eso la muestra
    /// que late no la está viendo nadie, y sigue costando lo mismo.
    static let animatedSwatchLimit = 4

    /// `signal` entra por parámetro en vez de llamar a
    /// `BeaconSignal.derived(...)` acá: el dueño de esa derivación es el
    /// store (hoy el id del beacon, mañana quizás un slot que elija el
    /// servidor), y este archivo no tiene por qué enterarse si cambia.
    static func build(
        incoming: [SafetyBeacon],
        mine: SafetyBeacon?,
        locallyAcked: Set<String>,
        signal: (SafetyBeacon) -> BeaconSignal
    ) -> [BeaconFeedEntry] {
        let ordered = incoming.sorted(by: priority)

        // El censo cuenta MI PROPIO faro aunque no tenga fila en esta lista:
        // si mi señal coincide con la de alguien que estoy viendo, las dos
        // están prendidas en el mismo salón y la ambigüedad es real.
        var census: [BeaconSignal: Int] = [:]
        var colorCensus: [BeaconIdentity: Int] = [:]
        for beacon in ordered where !beacon.isResolved {
            census[signal(beacon), default: 0] += 1
            colorCensus[signal(beacon).identity, default: 0] += 1
        }
        if let mine, !mine.isResolved {
            census[signal(mine), default: 0] += 1
            colorCensus[signal(mine).identity, default: 0] += 1
        }

        var liveSoFar = 0
        return ordered.map { beacon in
            let value = signal(beacon)
            let isLive = !beacon.isResolved
            if isLive { liveSoFar += 1 }
            return BeaconFeedEntry(
                beacon: beacon,
                signal: value,
                // Una fila resuelta ya no tiene a nadie parpadeando del otro
                // lado del salón, así que no puede confundirse con nada.
                signalIsAmbiguous: isLive && (census[value] ?? 0) > 1,
                // Sólo cuando el ritmo NO coincide: si coincide también, el
                // aviso fuerte de arriba ya lo dice y dos carteles seguidos
                // diciendo casi lo mismo se leen como ninguno.
                colorIsShared: isLive
                    && (colorCensus[value.identity] ?? 0) > 1
                    && (census[value] ?? 0) <= 1,
                animatesSwatch: isLive && liveSoFar <= animatedSwatchLimit,
                iAmOnMyWay: beacon.iAcked || locallyAcked.contains(beacon.id)
            )
        }
    }

    /// Cuántos siguen perdidos. Lo resuelto se muestra un par de minutos más
    /// a propósito, pero no es lo que hay que atender.
    static func liveCount(_ entries: [BeaconFeedEntry]) -> Int {
        entries.reduce(0) { $0 + ($1.beacon.isResolved ? 0 : 1) }
    }

    /// A QUIÉN MIRÁS PRIMERO.
    ///
    ///  1. El que sigue perdido, antes que el que ya apareció.
    ///  2. El que nadie de tu lado contestó. Si ya dijiste "voy", esa tarjeta
    ///     ya tiene dueño y puede bajar.
    ///  3. El que hace más rato que espera: `expiresAt` crece con
    ///     `createdAt`, así que el más viejo es también el que está más cerca
    ///     de quedarse sin faro.
    ///  4. Por id, para que el orden sea TOTAL. Sin este desempate dos filas
    ///     con el mismo instante se pueden intercambiar entre dos polls y la
    ///     tarjeta se mueve justo abajo del dedo que iba a tocarla.
    ///
    /// El punto 2 lee `iAcked` DEL SERVIDOR, nunca el acuse optimista: tocar
    /// "Voy" tiene que cambiar el botón en el acto y recién reordenar la
    /// lista cuando el backend confirma, un poll después. Al revés, la
    /// tarjeta se escapa de abajo del dedo en el mismo gesto.
    private static func priority(_ lhs: SafetyBeacon, _ rhs: SafetyBeacon) -> Bool {
        if lhs.isResolved != rhs.isResolved { return !lhs.isResolved }
        if lhs.iAcked != rhs.iAcked { return !lhs.iAcked }
        if lhs.expiresAt != rhs.expiresAt { return lhs.expiresAt < rhs.expiresAt }
        return lhs.id < rhs.id
    }
}
