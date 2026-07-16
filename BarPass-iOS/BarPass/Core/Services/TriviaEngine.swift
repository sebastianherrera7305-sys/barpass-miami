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

    /// Display strings are l10n keys resolved at the view via `L10n.shared.t(...)`.
    /// `id` and `correctIndex` are stable (persistence + scoring); option order
    /// is preserved so `correctIndex` stays valid across translations.
    static let pool: [TriviaQuestion] = [
        .init(id: "q1", question: "trivia.q1.question",
              options: ["trivia.q1.o0", "trivia.q1.o1", "trivia.q1.o2", "trivia.q1.o3"], correctIndex: 0,
              category: "trivia.cat.etiquette", funFact: "trivia.q1.fact"),
        .init(id: "q2", question: "trivia.q2.question",
              options: ["trivia.q2.o0", "trivia.q2.o1", "trivia.q2.o2", "trivia.q2.o3"], correctIndex: 1,
              category: "trivia.cat.dresscode", funFact: "trivia.q2.fact"),
        .init(id: "q3", question: "trivia.q3.question",
              options: ["trivia.q3.o0", "trivia.q3.o1", "trivia.q3.o2", "trivia.q3.o3"], correctIndex: 1,
              category: "trivia.cat.prices", funFact: "trivia.q3.fact"),
        .init(id: "q4", question: "trivia.q4.question",
              options: ["trivia.q4.o0", "trivia.q4.o1", "trivia.q4.o2", "trivia.q4.o3"], correctIndex: 1,
              category: "trivia.cat.venues", funFact: "trivia.q4.fact"),
        .init(id: "q5", question: "trivia.q5.question",
              options: ["trivia.q5.o0", "trivia.q5.o1", "trivia.q5.o2", "trivia.q5.o3"], correctIndex: 1,
              category: "trivia.cat.neighborhoods", funFact: "trivia.q5.fact"),
        .init(id: "q6", question: "trivia.q6.question",
              options: ["trivia.q6.o0", "trivia.q6.o1", "trivia.q6.o2", "trivia.q6.o3"], correctIndex: 2,
              category: "trivia.cat.etiquette", funFact: "trivia.q6.fact"),
        .init(id: "q7", question: "trivia.q7.question",
              options: ["trivia.q7.o0", "trivia.q7.o1", "trivia.q7.o2", "trivia.q7.o3"], correctIndex: 1,
              category: "trivia.cat.basics", funFact: "trivia.q7.fact"),
        .init(id: "q8", question: "trivia.q8.question",
              options: ["trivia.q8.o0", "trivia.q8.o1", "trivia.q8.o2", "trivia.q8.o3"], correctIndex: 1,
              category: "trivia.cat.culture", funFact: "trivia.q8.fact"),
        .init(id: "q9", question: "trivia.q9.question",
              options: ["trivia.q9.o0", "trivia.q9.o1", "trivia.q9.o2", "trivia.q9.o3"], correctIndex: 1,
              category: "trivia.cat.basics", funFact: "trivia.q9.fact"),
        .init(id: "q10", question: "trivia.q10.question",
              options: ["trivia.q10.o0", "trivia.q10.o1", "trivia.q10.o2", "trivia.q10.o3"], correctIndex: 2,
              category: "trivia.cat.timing", funFact: "trivia.q10.fact"),
        .init(id: "q11", question: "trivia.q11.question",
              options: ["trivia.q11.o0", "trivia.q11.o1", "trivia.q11.o2", "trivia.q11.o3"], correctIndex: 0,
              category: "trivia.cat.history", funFact: "trivia.q11.fact"),
        .init(id: "q12", question: "trivia.q12.question",
              options: ["trivia.q12.o0", "trivia.q12.o1", "trivia.q12.o2", "trivia.q12.o3"], correctIndex: 1,
              category: "trivia.cat.culture", funFact: "trivia.q12.fact"),
        .init(id: "q13", question: "trivia.q13.question",
              options: ["trivia.q13.o0", "trivia.q13.o1", "trivia.q13.o2", "trivia.q13.o3"], correctIndex: 2,
              category: "trivia.cat.prices", funFact: "trivia.q13.fact"),
        .init(id: "q14", question: "trivia.q14.question",
              options: ["trivia.q14.o0", "trivia.q14.o1", "trivia.q14.o2", "trivia.q14.o3"], correctIndex: 1,
              category: "trivia.cat.events", funFact: "trivia.q14.fact"),
        .init(id: "q15", question: "trivia.q15.question",
              options: ["trivia.q15.o0", "trivia.q15.o1", "trivia.q15.o2", "trivia.q15.o3"], correctIndex: 1,
              category: "trivia.cat.etiquette", funFact: "trivia.q15.fact"),
    ]
}
