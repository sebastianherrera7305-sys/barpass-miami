import Foundation
import SwiftUI

// MARK: - Model

struct TriviaQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let options: [String]
    let correctIndex: Int
    var puntos: Int = 100
    let category: String
    let funFact: String
}

// MARK: - Engine

/// One nightlife-trivia question per day (UTC cycle). A correct answer
/// awards XP through PointsEngine and counts toward missions.
@MainActor
final class TriviaEngine: ObservableObject {
    static let shared = TriviaEngine()
    private static let key = "bp_trivia_state"

    @Published var todayQuestion: TriviaQuestion?
    @Published var answeredToday = false
    @Published var lastAnswerCorrect: Bool?

    private struct State: Codable {
        var day: String
        var answered: Bool
        var correct: Bool?
    }

    private init() { loadTodayQuestion() }

    func loadTodayQuestion() {
        let pool = Self.pool
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 0
        todayQuestion = pool[dayOfYear % pool.count]

        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(State.self, from: data),
           s.day == Self.dayStamp() {
            answeredToday = s.answered
            lastAnswerCorrect = s.correct
        } else {
            answeredToday = false
            lastAnswerCorrect = nil
        }
    }

    /// Returns true on a correct answer (and awards XP once per day).
    @discardableResult
    func answer(_ index: Int) -> Bool {
        guard let q = todayQuestion, !answeredToday else { return false }
        let correct = index == q.correctIndex
        answeredToday = true
        lastAnswerCorrect = correct
        if correct {
            PointsEngine.shared.award(.triviaWin)
        }
        persist()
        return correct
    }

    private func persist() {
        let s = State(day: Self.dayStamp(), answered: answeredToday, correct: lastAnswerCorrect)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Question pool (Miami nightlife)

    static let pool: [TriviaQuestion] = [
        .init(id: "q1", question: "¿Cuál es el mejor horario para llegar a un club sin hacer fila?",
              options: ["Antes de 11:30 PM", "1 AM", "3 AM", "Después del cierre"], correctIndex: 0,
              category: "Etiqueta", funFact: "La mayoría de los clubs de Miami llenan su fila entre 12 y 1 AM."),
        .init(id: "q2", question: "¿Qué se considera dress code 'upscale' en South Beach?",
              options: ["Sneakers y shorts", "Sin gorras ni bermudas", "Disfraz completo", "Ropa de playa"], correctIndex: 1,
              category: "Dress code", funFact: "En LIV y Story el door staff rechaza sneakers deportivos casi siempre."),
        .init(id: "q3", question: "¿Cuánto puede costar una botella de Ace of Spades en un club top de Miami?",
              options: ["$200", "$800+", "$80", "$50"], correctIndex: 1,
              category: "Precios", funFact: "El markup de botellas en clubs es típicamente 8-10x el retail."),
        .init(id: "q4", question: "¿Qué club de Miami es famoso por estar abierto 24 horas?",
              options: ["LIV", "E11EVEN", "Story", "Basement"], correctIndex: 1,
              category: "Venues", funFact: "E11EVEN opera 24/7 los 365 días del año desde 2014."),
        .init(id: "q5", question: "¿Qué barrio es conocido por sus rooftops con vista al skyline?",
              options: ["Little Havana", "Brickell", "Hialeah", "Kendall"], correctIndex: 1,
              category: "Barrios", funFact: "Brickell tiene más de 10 rooftop bars en un radio de 1 km."),
        .init(id: "q6", question: "¿Cuál es la propina estándar para el bartender en Miami?",
              options: ["No se deja", "5%", "18-20%", "50%"], correctIndex: 2,
              category: "Etiqueta", funFact: "Muchos venues de Miami ya incluyen 18% de 'service charge' — revisá la cuenta."),
        .init(id: "q7", question: "¿Qué significa 'cover' en la puerta de un club?",
              options: ["El abrigo que dejás", "El costo de entrada", "La primera bebida", "El valet"], correctIndex: 1,
              category: "Básicos", funFact: "El cover en Miami puede variar la misma noche según la hora y el género."),
        .init(id: "q8", question: "¿Dónde nació el sonido del 'Miami Bass'?",
              options: ["South Beach", "Liberty City", "Wynwood", "Coral Gables"], correctIndex: 1,
              category: "Cultura", funFact: "El Miami Bass de los 80s influyó al hip-hop y al reggaeton actual."),
        .init(id: "q9", question: "¿Qué es 'bottle service'?",
              options: ["Delivery de licor", "Mesa VIP con botellas", "Barra libre", "El bartender"], correctIndex: 1,
              category: "Básicos", funFact: "El bottle service nació en clubs de NY en los 90s y Miami lo perfeccionó."),
        .init(id: "q10", question: "¿Cuál es la mejor noche para salir con menos multitud en Miami?",
              options: ["Sábado", "Viernes", "Jueves", "Domingo de Memorial Weekend"], correctIndex: 2,
              category: "Timing", funFact: "Los jueves muchos venues tienen ladies night y menos fila."),
        .init(id: "q11", question: "¿Qué venue histórico de Little Havana existe desde 1935?",
              options: ["Ball & Chain", "Mango's", "Hoy Como Ayer", "La Trova"], correctIndex: 0,
              category: "Historia", funFact: "En Ball & Chain tocaron Billie Holiday y Chet Baker."),
        .init(id: "q12", question: "¿Qué es el 'sunrise set' en la escena de Miami?",
              options: ["Yoga en la playa", "DJ set hasta el amanecer", "Desayuno buffet", "Un cóctel"], correctIndex: 1,
              category: "Cultura", funFact: "La Terrace de Club Space es legendaria por sus sets de 10+ horas."),
        .init(id: "q13", question: "¿Cuánto cuesta típicamente el valet en un club de South Beach?",
              options: ["Gratis", "$5", "$25-40", "$100"], correctIndex: 2,
              category: "Precios", funFact: "Parking en street en South Beach un sábado es casi imposible — llegá en Uber."),
        .init(id: "q14", question: "¿Qué festival convierte a Miami en la capital del EDM cada marzo?",
              options: ["Art Basel", "Ultra Music Festival", "Calle Ocho", "Rolling Loud"], correctIndex: 1,
              category: "Eventos", funFact: "Ultra atrae 165,000+ personas a Bayfront Park cada año."),
        .init(id: "q15", question: "¿Qué significa estar 'en la lista' de un club?",
              options: ["Estar vetado", "Entrada con descuento o gratis", "Ser el DJ", "Trabajar ahí"], correctIndex: 1,
              category: "Etiqueta", funFact: "Los promoters arman listas que te ahorran el cover antes de cierta hora."),
    ]
}
