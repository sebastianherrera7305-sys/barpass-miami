import Foundation

/// Las reglas que alguien acepta ANTES de su primera publicación, y el
/// recuerdo de que ya las aceptó.
///
/// POR QUÉ EXISTE, lo primero y más importante: las fotos y videos que se
/// suben desde adentro de un bar son PÚBLICOS de verdad. En
/// supabase/venue_media.sql la política de lectura es
/// `for select to anon, authenticated using (true)` y el bucket
/// `venue-media` está creado con `public = true`, así que cualquiera —
/// sin cuenta, sin app, con el link — las ve. Hasta hoy la app no lo decía
/// en ninguna pantalla: `checkin.moment.subtitle` dice "lo ve todo el
/// mundo en la página del lugar", que alguien puede leer como "todo el
/// mundo que esté en la app". Alguien que cree que le está mostrando la
/// foto a sus amigos está equivocado, y decirle la verdad es lo más útil
/// que hace este archivo.
///
/// Lo segundo es la directriz 1.2 de Apple, que pide un método para
/// filtrar contenido objetable *antes* de que se publique. Unas reglas
/// cortas, leídas y aceptadas explícitamente son la capa más barata que
/// existe, y es la que el revisor ve sin que nadie se la muestre.
struct PostingRule: Identifiable {
    /// SF Symbol. No hay assets nuevos en esta pieza a propósito: un ícono
    /// que falta se ve como un cuadrado vacío al lado de una regla.
    let symbol: String
    let key: String
    var id: String { key }
}

enum PostingRules {

    /// CADA REGLA EXISTE PORQUE EXISTE UN MOTIVO DE REPORTE.
    ///
    /// Ese es el criterio completo de esta lista, y es el que la mantiene
    /// honesta en las dos direcciones: un motivo de reporte sin regla
    /// castiga a alguien por algo que nunca le dijimos, y una regla sin
    /// motivo de reporte es una amenaza que nadie puede hacer cumplir.
    /// El mapeo contra `MediaReportReason` (Repositories/MediaReportRepository.swift),
    /// explícito para que se note si alguna vez se rompe:
    ///
    ///   nudity  → .sexual
    ///   minor   → .minor
    ///   respect → .violence, .hate, .harassment, .illegal
    ///   consent → .depictsMe
    ///   here    → .wrongVenue, .spam
    ///
    /// `.other` no tiene regla y no debe tenerla: es la vía de escape de
    /// quien reporta, no una prohibición.
    ///
    /// Son cinco y no cuatro por ese mapeo, no por ganas de escribir: las
    /// cinco caben en una pantalla sin scroll y se leen en diez segundos,
    /// que es el techo real de atención de alguien parado adentro de un bar.
    static let all: [PostingRule] = [
        PostingRule(symbol: "eye.slash", key: "posting.rule.nudity"),
        PostingRule(symbol: "person.crop.circle.badge.exclamationmark", key: "posting.rule.minor"),
        PostingRule(symbol: "hand.raised", key: "posting.rule.respect"),
        PostingRule(symbol: "person.2", key: "posting.rule.consent"),
        PostingRule(symbol: "mappin.and.ellipse", key: "posting.rule.here"),
    ]

    /// Versión del TEXTO aceptado. Si las reglas cambian de fondo (una
    /// regla nueva, una que se ablanda), sube el número y todos vuelven a
    /// aceptar. Una aceptación es de un texto concreto, no de la existencia
    /// de un texto; guardar sólo un booleano hace que el día que se agregue
    /// una regla nadie la haya aceptado nunca y nadie se entere.
    /// Una coma corregida NO es una versión nueva.
    static let version = 1

    private static let key = "bp_posting_rules_accepted"

    /// Tope duro, mismo criterio que `HiddenStories`: la lista se guarda
    /// entera y se lee en cada toque del botón de subir. Ocho cuentas
    /// distintas en un mismo teléfono ya es un caso raro (una persona y la
    /// cuenta de prueba); lo que se descarta al llenarse es lo más viejo, y
    /// el único costo de descartar de más es que esa cuenta lee las reglas
    /// una vez más.
    private static let limit = 8

    /// La cuenta a la que se le atribuye la aceptación, o `nil` sin sesión.
    ///
    /// Por cuenta y no por dispositivo: dos personas comparten un teléfono
    /// más seguido de lo que parece (se presta para que un amigo suba algo,
    /// se cierra sesión y entra otro), y una aceptación global haría que la
    /// segunda persona publique sin haber leído nunca las reglas. Es
    /// exactamente el caso que esta pieza existe para que no pase.
    ///
    /// `restoreSession()` es sincrónico pero emite un evento de analytics
    /// por llamada, así que se llama al tocar el botón y al aceptar — nunca
    /// desde el `body` de una vista, que se evalúa muchas veces por segundo.
    static func accountId() -> String? {
        AuthService.shared.restoreSession()?.user.id
    }

    static func hasAccepted(_ accountId: String?) -> Bool {
        guard let accountId else { return false }
        return stored().contains(token(for: accountId))
    }

    /// Sin sesión no se guarda nada: preferimos volver a preguntar a
    /// atribuirle una aceptación a un dispositivo. En la práctica no pasa
    /// —`RootView` exige auth antes del tab bar y el INSERT de
    /// `venue_media` pide `user_id = auth.uid()`— pero si alguna vez pasa,
    /// el error correcto es preguntar de más.
    static func accept(_ accountId: String?) {
        guard let accountId else { return }
        var ids = stored()
        let token = token(for: accountId)
        ids.removeAll { $0 == token }
        ids.append(token)
        if ids.count > limit { ids.removeFirst(ids.count - limit) }
        UserDefaults.standard.set(ids, forKey: key)
    }

    private static func token(for accountId: String) -> String { "\(accountId)#\(version)" }

    private static func stored() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
