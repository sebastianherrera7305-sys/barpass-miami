import SwiftUI

// MARK: - Persistence

/// Lo que el usuario contestó en el quiz de onboarding, guardado localmente.
///
/// Corre ANTES del login, así que en ese momento no existe usuario ni sesión:
/// no hay dónde escribir esto server-side todavía. Mismo patrón que
/// `AgeGateService` — se persiste en UserDefaults y `isSyncedToServer` queda
/// en false hasta que alguien lo suba una vez que el usuario ya existe.
///
/// Se guardan los `rawValue` de `ExperienceIntent` / `CompanyType` /
/// `InclusivePreference` (no índices ni texto traducido), así que el orden de
/// los enums puede cambiar sin corromper lo ya guardado, y lo almacenado entra
/// directo al `ExperienceScorer` sin traducción intermedia.
enum TasteProfileService {
    private static let intentsKey   = "bp_taste_intents"
    private static let companyKey   = "bp_taste_company"
    private static let prefsKey     = "bp_taste_prefs"
    private static let completedKey = "bp_taste_completed"
    private static let syncedKey    = "bp_taste_synced"

    /// True una vez que el usuario terminó (o salteó) el quiz. Igual que el
    /// age gate: se pregunta una sola vez por instalación.
    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static var intents: [ExperienceIntent] {
        (UserDefaults.standard.array(forKey: intentsKey) as? [String] ?? [])
            .compactMap(ExperienceIntent.init(rawValue:))
    }

    static var company: CompanyType? {
        UserDefaults.standard.string(forKey: companyKey).flatMap(CompanyType.init(rawValue:))
    }

    static var preferences: [InclusivePreference] {
        (UserDefaults.standard.array(forKey: prefsKey) as? [String] ?? [])
            .compactMap(InclusivePreference.init(rawValue:))
    }

    /// Queda en false hasta que estas respuestas se suban al perfil del
    /// usuario. Mismo rol que `AgeGateService.isSyncedToServer`: permite que
    /// un reintento posterior sepa si la escritura realmente llegó.
    static var isSyncedToServer: Bool {
        get { UserDefaults.standard.bool(forKey: syncedKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncedKey) }
    }

    static func save(intents: Set<String>, company: CompanyType?, preferences: Set<String>) {
        let d = UserDefaults.standard
        d.set(Array(intents), forKey: intentsKey)
        d.set(company?.rawValue, forKey: companyKey)
        d.set(Array(preferences), forKey: prefsKey)
        d.set(true, forKey: completedKey)
        // Respuestas nuevas todavía no subidas — que un re-quiz futuro no
        // quede marcado como ya sincronizado.
        d.set(false, forKey: syncedKey)
    }

    /// Marca el quiz como resuelto sin guardar respuestas (el usuario lo
    /// salteó). Sin esto volvería a aparecer en cada arranque.
    static func markSkipped() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func reset() {
        let d = UserDefaults.standard
        [intentsKey, companyKey, prefsKey, completedKey, syncedKey].forEach(d.removeObject(forKey:))
    }
}

// MARK: - View

/// Quiz de gustos del onboarding: 3 pasos cortos entre el video y el login.
///
/// Por qué acá y no después del login: el objetivo es que el usuario ya haya
/// invertido algo antes de que le pidamos crear cuenta — terminar algo propio
/// pesa más que una pantalla de registro en frío. El costo es que todavía no
/// hay usuario, y por eso las respuestas van a UserDefaults local
/// (`TasteProfileService`) y se reconcilian después.
///
/// NO pregunta edad a propósito: `AgeGateView` ya la pide (21+, requisito de
/// App Review) justo después del login, y preguntarla dos veces sería
/// fricción pura en la pantalla que menos la tolera.
///
/// Todo el vocabulario es el que ya usa la app — `ExperienceIntent`,
/// `CompanyType`, `InclusivePreference` — así que lo que se responde acá
/// alimenta directo al `ExperienceScorer`, y las 26 etiquetas ya están
/// traducidas a ES/EN/PT.
struct TasteQuizView: View {
    let onFinished: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var step = 0
    @State private var selectedIntents: Set<String> = []
    @State private var company: CompanyType?
    @State private var selectedPrefs: Set<String> = []

    private let totalSteps = 3
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        ZStack {
            BPBackgroundView()

            VStack(spacing: 20) {
                header

                ScrollView {
                    VStack(spacing: 10) {
                        switch step {
                        case 0:
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(ExperienceIntent.allCases) { intentChip($0) }
                            }
                        case 1:
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(CompanyType.allCases) { companyChip($0) }
                            }
                        default:
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(InclusivePreference.allCases) { prefChip($0) }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 380)

                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            // Indicador de progreso: arranca con el primer tramo ya pintado
            // para que el quiz se vea empezado y no en cero.
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.bpAmber : Color.bpInk.opacity(0.15))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .bpAccessibility(label: String(format: l10n.t("taste.progress.a11y"), step + 1, totalSteps))

            VStack(spacing: 8) {
                Text(l10n.t(titleKey))
                    .font(.bpTitle1())
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.center)
                Text(l10n.t(subtitleKey))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .id(step) // fuerza la transición de texto al cambiar de paso
            .transition(.opacity)
        }
    }

    private var titleKey: String {
        switch step {
        case 0:  return "taste.intents.title"
        case 1:  return "taste.company.title"
        default: return "taste.prefs.title"
        }
    }

    private var subtitleKey: String {
        switch step {
        case 0:  return "taste.intents.subtitle"
        case 1:  return "taste.company.subtitle"
        default: return "taste.prefs.subtitle"
        }
    }

    // MARK: Footer

    /// El paso 1 exige al menos una respuesta — es la que de verdad alimenta
    /// las recomendaciones. Los otros dos se pueden pasar de largo.
    private var canAdvance: Bool {
        step != 0 || !selectedIntents.isEmpty
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                BPHaptics.medium()
                advance()
            } label: {
                Text(l10n.t(step == totalSteps - 1 ? "taste.finish" : "taste.continue"))
                    .font(.bpHeadline())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                    .opacity(canAdvance ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
            .bpAccessibility(
                label: l10n.t(step == totalSteps - 1 ? "taste.finish" : "taste.continue"),
                hint: l10n.t("taste.continue.hint"),
                isButton: true
            )

            Button {
                BPHaptics.light()
                TasteProfileService.markSkipped()
                onFinished()
            } label: {
                Text(l10n.t("taste.skip"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("taste.skip"), hint: l10n.t("taste.skip.hint"), isButton: true)
        }
    }

    private func advance() {
        guard canAdvance else { return }
        if step < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        } else {
            TasteProfileService.save(
                intents: selectedIntents,
                company: company,
                preferences: selectedPrefs
            )
            BPHaptics.success()
            onFinished()
        }
    }

    // MARK: Chips
    // Mismo tratamiento visual que PromptYourNightView, para que el quiz no
    // se sienta una pantalla ajena al resto de la app.

    private func intentChip(_ intent: ExperienceIntent) -> some View {
        let on = selectedIntents.contains(intent.id)
        let label = l10n.t(intent.labelKey)
        return Button {
            BPHaptics.light()
            if on { selectedIntents.remove(intent.id) } else { selectedIntents.insert(intent.id) }
        } label: {
            chipBody(emoji: intent.emoji, label: label, on: on)
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("night.vibe.hint"), isButton: true)
    }

    private func companyChip(_ c: CompanyType) -> some View {
        let on = company == c
        let label = l10n.t(c.labelKey)
        return Button {
            BPHaptics.light()
            company = on ? nil : c
        } label: {
            chipBody(emoji: c.emoji, label: label, on: on)
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("context.company.hint"), isButton: true)
    }

    private func prefChip(_ pref: InclusivePreference) -> some View {
        let on = selectedPrefs.contains(pref.id)
        let label = l10n.t(pref.labelKey)
        return Button {
            BPHaptics.light()
            if on { selectedPrefs.remove(pref.id) } else { selectedPrefs.insert(pref.id) }
        } label: {
            chipBody(emoji: nil, label: label, on: on)
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("inclusive.hint"), isButton: true)
    }

    private func chipBody(emoji: String?, label: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            if let emoji { Text(emoji) }
            Text(label)
                .font(.bpScaled(12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? .black : Color.bpInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(on ? Color.bpAmber : Color.bpInk.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
    }
}

#Preview("Dark") {
    TasteQuizView(onFinished: {})
        .preferredColorScheme(.dark)
}
