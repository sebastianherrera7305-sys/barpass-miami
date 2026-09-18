import Foundation
import SwiftUI

// Pure value logic: no state, no I/O, no callbacks — nothing that can be
// entered from a background queue the way the BGTaskScheduler handler was in
// builds 22/26/50. Every type here is a Sendable value, so this file is
// callable from any isolation without a hop.

// MARK: - Identity

/// One person's beacon: a colour AND a rhythm, never one without the other.
///
/// Why both. Protanopia/deuteranopia (~1 in 12 men) collapses colour vision
/// onto one blue-yellow axis, where at most two of any four hues stay apart.
/// No palette fixes that — the rhythm is the half of the identity that
/// survives when the hue does not, so the two hues that COLLAPSE INTO EACH
/// OTHER always carry the two most different rhythms:
///   gold ↔ green  collapse for a deuteranope  → 2.78Hz vs 0.71Hz
///   cyan ↔ magenta collapse for a protanope   → blinks vs never blinks
///
/// Declaration order is assignment order, so a group of two gets `gold` and
/// `cyan` — the pair that is furthest apart on the blue-yellow axis and thus
/// the only pair that is safe for every kind of colour vision.
///
/// Rejected deliberately: WHITE (brightest, but every other phone in the bar
/// shows a white-ish screen — camouflage, and strobes are white too); RED
/// (Y 0.21, first thing a protanope loses, and club wash is full of it); PURE
/// BLUE (Y 0.07, the weakest light a screen makes); ORANGE (19° from gold).
enum BeaconIdentity: String, CaseIterable, Sendable, Hashable, Codable, Identifiable {
    /// Y 0.60, hue 46°. The yellow end of the one axis dichromats keep; R+G
    /// at full, blue at zero — no hue this saturated is brighter except white.
    case gold
    /// Y 0.64, hue 186°. The blue end of that same axis, far brighter than
    /// pure blue because it borrows the green subpixel.
    case cyan
    /// Y 0.73, the brightest of the four. Hue 120°, in the widest remaining
    /// gap (gold 46° → cyan 186°).
    case green
    /// Y 0.28 — the weakest, unavoidably: the whole red-to-magenta arc is dim
    /// and this is its brightest point. Hue 307°. Gets `solid` (100% duty) so
    /// its time-averaged output lands with the others, not a fifth of them.
    case magenta

    var id: String { rawValue }

    var beaconColor: BeaconColor {
        switch self {
        case .gold: BeaconColor(red: 1.00, green: 0.76, blue: 0.00)
        case .cyan: BeaconColor(red: 0.00, green: 0.90, blue: 1.00)
        case .green: BeaconColor(red: 0.20, green: 1.00, blue: 0.20)
        case .magenta: BeaconColor(red: 1.00, green: 0.10, blue: 0.90)
        }
    }

    /// El ritmo en la variante 0. Existe para los llamadores que no tienen
    /// grupo a mano; lo real es `rhythm(in:)`.
    var rhythm: BeaconRhythm { rhythm(in: .zero) }

    /// POR QUÉ HAY VARIANTES. Cuatro identidades alcanzan para distinguirte
    /// DE TU GRUPO. No alcanzan para distinguirte DEL SALÓN: si cinco grupos
    /// levantan el faro en el mismo bar, hay cinco personas en dorado y el
    /// color deja de identificar a nadie. La variante rota los ritmos según
    /// el grupo, así que dos desconocidos colisionan sólo si comparten color
    /// Y ritmo — pasa de garantizado a 1 en 10.
    ///
    /// La rotación NO es libre. Dos restricciones la atan:
    ///  · `gold` y `green` se funden para un deuteránope, y `cyan` y
    ///    `magenta` para un protánope. Cada par colapsado lleva SIEMPRE los
    ///    dos ritmos más distintos entre sí. Ninguna variante le da a
    ///    gold/green el par débil (parpadeo lento vs doble: mismo período,
    ///    imposible de separar de un vistazo).
    ///  · `magenta` es el color más oscuro (Y 0.28) y no puede bajar el duty,
    ///    así que sólo alterna entre `solid` (100%) y `longPulse` (80%) — y
    ///    `longPulse` sólo aparece cuando `cyan` lleva `doubleBlink`, que es
    ///    su opuesto en duty.
    func rhythm(in variant: BeaconVariant) -> BeaconRhythm {
        switch (variant.index, self) {
        case (1, .gold): return .slowBlink
        case (3, .gold): return .doubleBlink
        case (_, .gold): return .fastFlicker

        case (2, .cyan), (3, .cyan): return .slowBlink
        case (_, .cyan): return .doubleBlink

        case (1, .green), (3, .green): return .fastFlicker
        case (2, .green): return .doubleBlink
        case (_, .green): return .slowBlink

        case (1, .magenta): return .longPulse
        case (_, .magenta): return .solid
        }
    }

    /// l10n key for the shoutable colour name ("DORADO", "CELESTE"...).
    var colorNameKey: String { "safety.beacon.color.\(rawValue)" }

    /// El índice con el que el servidor nombra este color
    /// (`safety_beacons.signal_index`, safety_beacon.sql §1). El contrato es
    /// el ORDEN DE DECLARACIÓN de este enum — 0 gold, 1 cyan, 2 green,
    /// 3 magenta — así que vive acá, pegado a la declaración, y no en el
    /// repositorio: reordenar los `case` de arriba sin mirar esto le
    /// cambiaría el color a todos los faros ya guardados.
    ///
    /// Falla en vez de recortar: un índice fuera de rango no es un faro
    /// tenue, es una fila que no entendemos, y el llamador tiene que caer
    /// al derivado del id — que los dos teléfonos calculan igual.
    init?(signalIndex: Int) {
        let palette = Self.allCases
        guard palette.indices.contains(signalIndex) else { return nil }
        self = palette[signalIndex]
    }
}

// MARK: - Signal

/// Lo que de verdad se muestra: un color Y un ritmo. Nunca uno sin el otro —
/// el color se corrompe con las luces del lugar y se pierde para un
/// dicrómata; el ritmo es la mitad que sobrevive.
struct BeaconSignal: Sendable, Hashable {
    let identity: BeaconIdentity
    let rhythm: BeaconRhythm

    /// Color y ritmo derivados del id del beacon, sin coordinar nada.
    ///
    /// Funciona porque ese id lo tienen LOS DOS LADOS: el servidor se lo dio
    /// a quien levantó la mano y aparece igual en el feed de quien lo busca.
    /// Misma entrada, mismo hash publicado, misma señal — sin una ronda de
    /// red extra justo en el momento en que la red del lugar está peor.
    ///
    /// Lo que esto NO resuelve: dos beacons simultáneos de grupos distintos
    /// en el mismo bar pueden caer en la misma señal (1 en 10). Para eso el
    /// servidor elige el slot libre al levantar la mano; esto es el piso que
    /// funciona aunque esa parte no esté.
    static func derived(fromBeaconId beaconId: String) -> BeaconSignal {
        let hash = BeaconIdentity.fnv1a64(beaconId + "\u{1F}signal")
        let palette = BeaconIdentity.allCases
        let identity = palette[Int(hash % UInt64(palette.count))]
        let variant = BeaconVariant(groupId: beaconId)
        return BeaconSignal(identity: identity, rhythm: identity.rhythm(in: variant))
    }

    /// El slot que el servidor eligió MIRANDO LA SALA: de todos los faros
    /// vivos en ese mismo bar, el (color, ritmo) menos usado
    /// (`raise_safety_beacon`, safety_beacon.sql §4). Es lo único que
    /// `derived(fromBeaconId:)` no puede hacer — un hash no sabe quién más
    /// levantó la mano en la misma habitación.
    ///
    /// `nil` cuando el par no se entiende (índice fuera de rango, o una de
    /// las dos mitades sin la otra). No se recorta ni se completa: media
    /// señal no se puede dibujar, y el llamador ya tiene un piso correcto
    /// al que caer.
    static func server(index: Int, variant: Int) -> BeaconSignal? {
        guard let identity = BeaconIdentity(signalIndex: index),
              let variant = BeaconVariant(serverIndex: variant) else { return nil }
        return BeaconSignal(identity: identity, rhythm: identity.rhythm(in: variant))
    }

    var color: BeaconColor { identity.beaconColor }
    var colorNameKey: String { identity.colorNameKey }
    var rhythmNameKey: String { rhythm.nameKey }
}

// MARK: - Variant

/// Cuál de las cuatro rotaciones de ritmo le toca a un grupo. Derivada del
/// groupId con el mismo hash publicado que el ranking, así que los dos
/// teléfonos llegan al mismo número sin hablarse.
struct BeaconVariant: Sendable, Hashable {
    let index: Int

    static let zero = BeaconVariant(index: 0)
    static let count = 4

    private init(index: Int) { self.index = index }

    /// La variante que eligió el servidor (`safety_beacons.signal_variant`).
    /// Failable por la misma razón que `BeaconIdentity(signalIndex:)`: un
    /// número que no es una de las cuatro rotaciones es dato corrupto, no
    /// una rotación nueva.
    init?(serverIndex: Int) {
        guard (0 ..< Self.count).contains(serverIndex) else { return nil }
        self.init(index: serverIndex)
    }

    init(groupId: String) {
        // El hash del ranking lleva el memberId adentro; acá se mezcla sólo
        // el grupo, con un sufijo distinto para que las dos derivaciones no
        // queden correlacionadas.
        index = Int(BeaconIdentity.fnv1a64(groupId + "\u{1F}variant") % UInt64(Self.count))
    }
}

// MARK: - Assignment

/// `noSignalAvailable` and `notInGroup` are different facts that must not both
/// collapse to `nil`: "we know, there is none" vs "we were never told about
/// this person". Neither may be drawn as a beacon.
enum BeaconLookup: Sendable, Hashable {
    case assigned(BeaconIdentity)
    case noSignalAvailable
    case notInGroup
}

/// Order- and device-independent: two phones holding the same member ids
/// produce identical results, with no network and no coordination.
struct BeaconAssignment: Sendable, Hashable {
    let groupId: String
    let variant: BeaconVariant
    let assigned: [String: BeaconIdentity]
    /// Members past the fourth, in the same canonical order used to assign.
    let withoutSignal: [String]

    /// El color y el ritmo juntos, que es lo único dibujable. `nil` significa
    /// exactamente lo mismo que `lookup` devuelve como no-asignado: no hay
    /// faro para esta persona, y eso se muestra, no se disimula.
    func signal(for memberId: String) -> BeaconSignal? {
        guard let identity = assigned[memberId] else { return nil }
        return BeaconSignal(identity: identity, rhythm: identity.rhythm(in: variant))
    }

    func lookup(_ memberId: String) -> BeaconLookup {
        if let identity = assigned[memberId] { return .assigned(identity) }
        return withoutSignal.contains(memberId) ? .noSignalAvailable : .notInGroup
    }

    func identity(for memberId: String) -> BeaconIdentity? { assigned[memberId] }

    var coversWholeGroup: Bool { withoutSignal.isEmpty }
}

extension BeaconIdentity {
    /// Stable per-group assignment. A function of `(memberId, groupId)` ALONE
    /// cannot do this job: two members land on the same slot whenever their
    /// hashes agree mod 4, which is exactly the collision this feature exists
    /// to prevent. So the input is the member SET, canonicalised before use —
    /// ranked by hash, tie-broken by id — which makes the result independent
    /// of the order the list arrived in while still needing no agreement
    /// between devices.
    ///
    /// Past the fourth member the honest answer is that there is none. The
    /// tempting alternative — reuse a colour with a different rhythm — puts
    /// two people in the same hue in a dark room, and telling them apart then
    /// costs a full uninterrupted cycle of staring, which a crowd never gives
    /// you. A wrong beacon is worse than none: it sends the group confidently
    /// to the wrong person.
    /// `prioritising` es quien levantó la mano. Sin esto el corte lo decide
    /// sólo el hash, así que en un grupo de seis la persona que se separó
    /// puede caer quinta y quedarse sin faro — justo la única que lo
    /// necesita. Con esto, quien emite entra primero y el resto se ordena
    /// detrás por el mismo ranking canónico de siempre; todos los teléfonos
    /// llegan al mismo resultado porque todos reciben del servidor el mismo
    /// emisor.
    static func assign(memberIds: [String], groupId: String, prioritising: [String] = []) -> BeaconAssignment {
        var seen = Set<String>()
        let unique: [String] = memberIds.filter { seen.insert($0).inserted }
        // Ids are unique by now, so the id tiebreak makes this a strict total
        // order: the same set ranks the same way whatever order it arrived in.
        var ranked: [(key: UInt64, id: String)] = unique.map {
            (key: rank(memberId: $0, groupId: groupId), id: $0)
        }
        // Los priorizados se ordenan entre sí con el MISMO ranking, así que
        // dos emisores simultáneos no dependen del orden en que llegaron.
        let priority = Set(prioritising)
        ranked.sort { lhs, rhs in
            let lp = priority.contains(lhs.id), rp = priority.contains(rhs.id)
            if lp != rp { return lp }
            return lhs.key == rhs.key ? lhs.id < rhs.id : lhs.key < rhs.key
        }

        let palette: [BeaconIdentity] = allCases
        var assigned: [String: BeaconIdentity] = [:]
        for (slot, entry) in ranked.prefix(palette.count).enumerated() {
            assigned[entry.id] = palette[slot]
        }
        let overflow: [String] = ranked.dropFirst(palette.count).map { $0.id }
        return BeaconAssignment(
            groupId: groupId, variant: BeaconVariant(groupId: groupId),
            assigned: assigned, withoutSignal: overflow
        )
    }

    static func rank(memberId: String, groupId: String) -> UInt64 {
        // U+001F between the two so ("ab","c") and ("a","bc") cannot collide.
        fnv1a64(groupId + "\u{1F}" + memberId)
    }

    /// FNV-1a 64. Swift's own `Hasher` is seeded per process, so `hashValue`
    /// differs between two launches of the SAME app on the SAME phone — using
    /// it here would hand two friends different colours for the same group and
    /// the bug would only ever appear in someone's hands, never in a test.
    /// This is fixed, published, and byte-identical everywhere.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
