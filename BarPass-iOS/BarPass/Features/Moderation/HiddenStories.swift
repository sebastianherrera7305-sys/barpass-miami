import Foundation

/// Las fotos que ESTE teléfono no quiere volver a ver.
///
/// "Ocultar" no es "reportar". Reportar acusa a alguien y va al servidor;
/// ocultar es "no quiero ver esto" y no acusa a nadie — no debería costarle
/// a quien la subió ni un punto de reputación, ni dejar rastro en ninguna
/// cola de revisión. Por eso vive acá y no en la base: el servidor no tiene
/// por qué enterarse de los gustos de nadie.
///
/// El costo de esa decisión, dicho: es por dispositivo. Si la persona cambia
/// de teléfono, las fotos que ocultó vuelven. Es el precio de que ocultar no
/// genere un registro de quién no quiere ver qué, y me parece el lado
/// correcto del intercambio.
///
/// `nonisolated` a propósito: lo lee el repositorio, que es un actor, y lo
/// escribe la vista, que es @MainActor. UserDefaults es seguro desde
/// cualquier hilo; un `@MainActor` acá obligaría al actor a saltar de
/// isolation en medio de una lectura de red.
enum HiddenStories {
    private static let key = "bp_hidden_story_ids"
    /// Tope duro. La lista se guarda entera en UserDefaults y se lee en cada
    /// carga de historias; sin techo, alguien que oculta cada noche durante
    /// un año la convierte en un costo permanente por una preferencia que ya
    /// no le importa a nadie. Al llenarse se descarta lo más viejo — las
    /// historias vencen en una noche, así que un id viejo ya no existe.
    private static let limit = 500

    static func hide(_ mediaId: String) {
        var ids = all()
        ids.removeAll { $0 == mediaId }
        ids.append(mediaId)
        if ids.count > limit { ids.removeFirst(ids.count - limit) }
        UserDefaults.standard.set(ids, forKey: key)
    }

    static func unhide(_ mediaId: String) {
        UserDefaults.standard.set(all().filter { $0 != mediaId }, forKey: key)
    }

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func contains(_ mediaId: String) -> Bool { all().contains(mediaId) }

    /// El filtro que aplica el repositorio. Un solo `Set` por lectura en vez
    /// de un `contains` lineal por fila.
    static func filtered<T>(_ items: [T], id: (T) -> String) -> [T] {
        let hidden = Set(all())
        guard !hidden.isEmpty else { return items }
        return items.filter { !hidden.contains(id($0)) }
    }
}
