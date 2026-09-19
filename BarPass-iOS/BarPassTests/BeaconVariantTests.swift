import XCTest
@testable import BarPass_app

/// Las variantes existen para que dos grupos distintos en el MISMO bar no
/// terminen con la misma señal. Pero rotar los ritmos libremente rompería lo
/// que hace que la paleta funcione, así que la rotación está atada a
/// restricciones que un comentario no puede garantizar. Esto las garantiza.
final class BeaconVariantTests: XCTestCase {

    private var variants: [BeaconVariant] {
        // Se construyen por groupId, que es la única vía pública. Se buscan
        // ids que caigan en cada índice en vez de fabricar la variante a
        // mano: así el test también cubre la derivación.
        var found: [Int: BeaconVariant] = [:]
        var n = 0
        while found.count < BeaconVariant.count && n < 10_000 {
            let v = BeaconVariant(groupId: "grupo-\(n)")
            found[v.index] = v
            n += 1
        }
        XCTAssertEqual(found.count, BeaconVariant.count, "el hash no alcanza las 4 variantes")
        return found.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Dentro de un grupo, dos personas nunca comparten ritmo. Si esto se
    /// rompe, dos personas quedan idénticas para alguien que no distingue
    /// sus colores.
    func test_dentroDeCadaVariante_losCuatroRitmosSonDistintos() {
        for variant in variants {
            let ids = BeaconIdentity.allCases.map { $0.rhythm(in: variant).id }
            XCTAssertEqual(Set(ids).count, 4, "variante \(variant.index) repite ritmo: \(ids)")
        }
    }

    /// gold y green se funden en un solo color para un deuteránope, y cyan y
    /// magenta para un protánope. El par que colapsa tiene que llevar los dos
    /// ritmos MÁS distintos, porque el ritmo es lo único que le queda a esa
    /// persona para separarlos.
    ///
    /// El par prohibido es slowBlink + doubleBlink: período casi igual
    /// (1400 vs 1300 ms), los dos "lentos", imposibles de separar en el
    /// vistazo de 300 ms que da una multitud. Que sean distintos NO alcanza.
    func test_losParesQueColapsanNuncaLlevanLosDosRitmosMasParecidos() {
        let prohibido = Set([BeaconRhythm.slowBlink.id, BeaconRhythm.doubleBlink.id])
        for variant in variants {
            for (a, b) in [(BeaconIdentity.gold, BeaconIdentity.green),
                           (BeaconIdentity.cyan, BeaconIdentity.magenta)] {
                let par = Set([a.rhythm(in: variant).id, b.rhythm(in: variant).id])
                XCTAssertNotEqual(
                    par, prohibido,
                    "variante \(variant.index): \(a.rawValue)/\(b.rawValue) llevan el par indistinguible"
                )
            }
        }
    }

    /// magenta es el color más oscuro de los cuatro (Y 0.28) y la pantalla es
    /// la fuente de luz: bajarle el duty lo apaga. Sólo puede llevar ritmos
    /// de duty alto.
    func test_magentaSiempreLlevaUnRitmoDeDutyAlto() {
        for variant in variants {
            let rhythm = BeaconIdentity.magenta.rhythm(in: variant)
            XCTAssertGreaterThanOrEqual(
                rhythm.dutyCycle, 0.75,
                "variante \(variant.index): magenta con \(rhythm.id) (duty \(rhythm.dutyCycle)) queda demasiado oscuro"
            )
        }
    }

    /// El número que justifica toda la rotación: 10 señales distintas en la
    /// sala, no 4. Si alguien agrega una variante que repite una combinación
    /// ya existente, este test lo dice — la rotación habría costado
    /// complejidad sin comprar separación.
    func test_lasVariantesProducenDiezSenalesDistintas() {
        var señales = Set<String>()
        for variant in variants {
            for identity in BeaconIdentity.allCases {
                señales.insert("\(identity.rawValue)/\(identity.rhythm(in: variant).id)")
            }
        }
        XCTAssertEqual(señales.count, 10, "señales distintas: \(señales.sorted())")
    }

    /// Ningún ritmo puede pasar los 3 destellos por segundo, que es el umbral
    /// de epilepsia fotosensible de WCAG 2.3.1. La pantalla se apunta a
    /// desconocidos en un cuarto oscuro que nunca aceptaron un estrobo.
    func test_ningunRitmoDeNingunaVarianteSuperaTresDestellosPorSegundo() {
        for variant in variants {
            for identity in BeaconIdentity.allCases {
                let rhythm = identity.rhythm(in: variant)
                XCTAssertLessThanOrEqual(
                    rhythm.maxFlashesPerSecond, 3,
                    "variante \(variant.index), \(identity.rawValue): \(rhythm.id) destella \(rhythm.maxFlashesPerSecond) veces por segundo"
                )
            }
        }
    }

    /// La linterna y la pantalla tienen que correr el MISMO patrón. Un ritmo
    /// continuo no se puede expresar como pasos alternados, así que el puente
    /// bifurca; si alguien agrega un ritmo que la capa de hardware recorta,
    /// la linterna corre otra cosa que la pantalla y de lejos eso es una
    /// quinta señal que no es de nadie.
    func test_ningunRitmoLlegaRecortadoALaLinterna() {
        for rhythm in BeaconRhythm.all {
            XCTAssertFalse(
                rhythm.flarePattern.wasClamped,
                "\(rhythm.id) lo recorta la capa de linterna: pantalla y linterna correrían patrones distintos"
            )
        }
    }

    /// Quien levantó la mano no puede quedarse sin faro por caer quinto en el
    /// ranking — es la única persona del grupo que lo necesita.
    func test_quienEmiteSiempreTieneSenal() {
        let miembros = (1 ... 9).map { "miembro-\($0)" }
        for perdido in miembros {
            let a = BeaconIdentity.assign(memberIds: miembros, groupId: "g1", prioritising: [perdido])
            XCTAssertNotNil(a.signal(for: perdido), "\(perdido) quedó sin señal siendo el que emite")
        }
    }

    /// Y priorizar no puede romper el determinismo: los dos teléfonos reciben
    /// del servidor el mismo emisor, así que tienen que llegar al mismo
    /// reparto aunque la lista les llegue en otro orden.
    func test_priorizarSigueSiendoDeterministico() {
        let miembros = (1 ... 7).map { "miembro-\($0)" }
        let a = BeaconIdentity.assign(memberIds: miembros, groupId: "g1", prioritising: ["miembro-6"])
        let b = BeaconIdentity.assign(memberIds: miembros.reversed(), groupId: "g1", prioritising: ["miembro-6"])
        XCTAssertEqual(a.assigned, b.assigned)
        XCTAssertEqual(a.withoutSignal.sorted(), b.withoutSignal.sorted())
    }
}
