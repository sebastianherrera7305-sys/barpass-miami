import SwiftUI

/// LA IDENTIDAD VISUAL DEL PUNTO DE ENCUENTRO — la luz que enciende el líder
/// ("estamos acá"), distinta de la del auxilio ("estoy acá, vengan"), que es el
/// faro que ya existe y enciende quien está en problemas.
///
/// Son dos gestos con dos significados, y un local oscuro a las tres de la
/// mañana no perdona que se parezcan. Por eso este archivo existe: la
/// diferencia vive en UN lugar, con su razón, y un test comprueba que no se
/// pueda confundir con ninguna señal que el auxilio sea capaz de producir.
///
/// POR QUÉ NO ES UN QUINTO COLOR. El propio `BeaconIdentity` documenta que la
/// paleta está agotada, y por qué: BLANCO se descartó (cualquier otro teléfono
/// del bar muestra una pantalla blanquecina: camuflaje), ROJO (el primero que
/// pierde un protanope, y la iluminación del club está llena de rojo), AZUL
/// PURO (Y 0,07, la luz más débil que hace una pantalla) y NARANJA (a 19° del
/// dorado). Inventar un color nuevo acá sería romper, sin que nadie lo decida,
/// el análisis de daltonismo de Sebastián.
///
/// Lo que sí hay son COMBINACIONES LIBRES. El auxilio nunca empareja `gold` con
/// `longPulse`: `BeaconIdentity.rhythm(in:)` le da a `gold` sólo
/// `fastFlicker`, `slowBlink` y `doubleBlink`. `longPulse` — 1200 ms encendido,
/// 300 ms apagado, 80% de duty, una vez por 1,5 s — se lee como "fija, pero
/// late": una referencia que se queda quieta, no una que llama a los gritos.
/// Nunca supera un destello por segundo (WCAG 2.3.1), y su fase apagada de
/// 300 ms supera el piso de 180 ms de la capa de linterna.
///
/// LÍMITE, dicho sin adornos: el dorado también es un color del auxilio, así
/// que a lo lejos el color solo NO alcanza para distinguirlos; los distingue
/// el ritmo (dorado que late largo y quieto vs. dorado que titila o hace
/// blip-blip) y, sobre todo, el CONTEXTO: el punto de encuentro sólo lo enciende
/// el líder y sólo aparece cuando su grupo ya lo está buscando con el radar.
/// (La pantalla del punto de encuentro queda FIJA; el diseño del auxilio hace
/// latir también la pantalla con su ritmo.)
///
/// ES UNA PROPUESTA. Es el valor por defecto más seguro que se puede sostener
/// con las reglas ya escritas, no una decisión de producto tomada: cambiar
/// `identity` y `rhythm` acá es todo lo que hace falta, y
/// `test_rallyPoint_isNotAnyAuxilioSignal` avisa si la nueva pareja pisa una
/// del auxilio.
enum RallyPointIdentity {
    static let identity: BeaconIdentity = .gold
    static let rhythm: BeaconRhythm = .longPulse

    /// El color de la pantalla completa del punto de encuentro.
    static var color: Color { identity.beaconColor.color }

    /// LO ESTÉTICO QUE SE PUEDE TOCAR SIN RIESGO (ver "Cambios estéticos" en el
    /// README): el tamaño máximo de la mascota en pantalla completa. No cambia
    /// ninguna regla de seguridad. Lo que SÍ afecta la seguridad (ritmo, y la
    /// pulsación larga de 1,2 s para apagar) tiene su propia advertencia donde
    /// vive.
    static let mascotMaxSize: CGFloat = 220

    /// El patrón de la linterna, derivado del mismo ritmo que la pantalla.
    static var flarePattern: FlarePattern { rhythm.flarePattern }
}
