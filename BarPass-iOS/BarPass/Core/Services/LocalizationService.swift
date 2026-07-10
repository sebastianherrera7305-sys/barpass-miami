import SwiftUI

/// Runtime language switching (ES / EN / PT) — no app restart needed.
/// Views observe `L10n.shared` and re-render on change; the choice persists
/// in UserDefaults. Adding a language = one dictionary. Keys missing in a
/// language fall back to Spanish (the authoring language).
enum AppLanguage: String, CaseIterable, Identifiable {
    case es, en, pt
    var id: String { rawValue }

    var flag: String {
        switch self {
        case .es: return "🇪🇸"
        case .en: return "🇺🇸"
        case .pt: return "🇧🇷"
        }
    }

    var label: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        case .pt: return "Português"
        }
    }
}

@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()
    private static let key = "bp_language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        language = saved.flatMap(AppLanguage.init) ?? .es
    }

    /// Translate a key. Falls back to Spanish, then to the key itself.
    func t(_ key: String) -> String {
        Self.tables[language]?[key] ?? Self.tables[.es]?[key] ?? key
    }

    private static let tables: [AppLanguage: [String: String]] = [
        .es: [
            "tab.tonight": "Tonight", "tab.explore": "Explorar", "tab.trips": "Trips",
            "tab.plan": "Plan", "tab.me": "Yo",
            "greet.morning": "Buenos días", "greet.afternoon": "Buenas tardes", "greet.night": "Buenas noches",
            "home.where": "¿A dónde esta noche?",
            "profile.language": "Idioma",
            "profile.points": "BarPass Points", "profile.nextLevel": "Próximo nivel",
            "profile.howToEarn": "Cómo ganar puntos",
            "profile.checkins": "Check-ins", "profile.reviews": "Reviews", "profile.invited": "Invitados",
            "explore.search": "Buscar venues…",
            "trips.title": "Trips", "trips.subtitle": "Planeá tu noche con tu gente",
            "trips.new": "Nuevo", "trips.mine": "Mis trips",
            "night.question": "¿Qué noche buscás?",
            "night.hint": "Elegí un vibe o describilo. Yo armo la noche.",
            "night.build": "Armá mi noche", "night.rebuild": "Armá otra noche",
            "night.yours": "Tu noche", "night.save": "Guardar como Trip",
        ],
        .en: [
            "tab.tonight": "Tonight", "tab.explore": "Explore", "tab.trips": "Trips",
            "tab.plan": "Plan", "tab.me": "Me",
            "greet.morning": "Good morning", "greet.afternoon": "Good afternoon", "greet.night": "Good evening",
            "home.where": "Where to tonight?",
            "profile.language": "Language",
            "profile.points": "BarPass Points", "profile.nextLevel": "Next level",
            "profile.howToEarn": "How to earn points",
            "profile.checkins": "Check-ins", "profile.reviews": "Reviews", "profile.invited": "Invited",
            "explore.search": "Search venues…",
            "trips.title": "Trips", "trips.subtitle": "Plan your night with your crew",
            "trips.new": "New", "trips.mine": "My trips",
            "night.question": "What kind of night?",
            "night.hint": "Pick a vibe or describe it. I'll build the night.",
            "night.build": "Build my night", "night.rebuild": "Build another one",
            "night.yours": "Your night", "night.save": "Save as Trip",
        ],
        .pt: [
            "tab.tonight": "Tonight", "tab.explore": "Explorar", "tab.trips": "Trips",
            "tab.plan": "Plano", "tab.me": "Eu",
            "greet.morning": "Bom dia", "greet.afternoon": "Boa tarde", "greet.night": "Boa noite",
            "home.where": "Para onde hoje à noite?",
            "profile.language": "Idioma",
            "profile.points": "BarPass Points", "profile.nextLevel": "Próximo nível",
            "profile.howToEarn": "Como ganhar pontos",
            "profile.checkins": "Check-ins", "profile.reviews": "Avaliações", "profile.invited": "Convidados",
            "explore.search": "Buscar lugares…",
            "trips.title": "Trips", "trips.subtitle": "Planeje sua noite com sua galera",
            "trips.new": "Novo", "trips.mine": "Meus trips",
            "night.question": "Que noite você quer?",
            "night.hint": "Escolha um vibe ou descreva. Eu monto a noite.",
            "night.build": "Montar minha noite", "night.rebuild": "Montar outra",
            "night.yours": "Sua noite", "night.save": "Salvar como Trip",
        ],
    ]
}
