import SwiftUI
import UIKit

/// Cómo se llega a BarPass desde afuera de BarPass.
///
/// Apple (directriz 1.2) pide que los datos de contacto estén PUBLICADOS y
/// alcanzables desde la app. Hasta hoy los únicos links legales vivían en
/// `NativeAuthView`, o sea en la pantalla de login: un revisor que ya entró
/// no la vuelve a ver nunca. Por eso esto cuelga de Perfil.
///
/// ⚠️ A CONFIRMAR — VERIFICADO POR SEBASTIÁN EL 2026-09-19, NO POR ESTE CÓDIGO:
/// el dominio `barpass.app` NO TIENE REGISTROS MX, así que hoy un mail a la
/// dirección de abajo REBOTA. La pantalla se construye igual —Apple exige el
/// contacto, y el arreglo es del lado del dominio, no del código— pero la
/// dirección vive en UNA sola constante para que mudarla sea una línea. Se
/// confirma mandando un mail desde una casilla externa y esperando el rebote.
enum BarPassSupport {

    /// ⚠️ LA DIRECCIÓN DE SOPORTE. CAMBIARLA ES ESTA LÍNEA Y NINGUNA OTRA.
    static let email = "support@barpass.app"

    /// Las dos páginas que hoy están DEPLOYADAS y responden
    /// (`src/app/legal/terms` y `src/app/legal/privacy`).
    ///
    /// Hay además un `src/app/contact/page.tsx` recién escrito en el repo,
    /// pero todavía sin deployar, y esta pantalla NO lo linkea: un link a un
    /// 404 en la pantalla que el revisor abre a buscar el contacto es peor
    /// que no tener el link. Cuando `https://barpass-v2.vercel.app/contact`
    /// responda de verdad, agregarlo es una constante más acá y una
    /// `LegalRow` allá abajo.
    static let terms = URL(string: "https://barpass-v2.vercel.app/legal/terms")!
    static let privacy = URL(string: "https://barpass-v2.vercel.app/legal/privacy")!

    /// Versión y build al pie del mail: sin esto, la mitad de los mensajes
    /// llegan sin decir contra qué build pasó lo que pasó.
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// `mailto:` armado con `URLComponents`, no concatenando strings: el
    /// asunto y el cuerpo llevan espacios y acentos, y un `mailto:` mal
    /// escapado no falla con un error — abre el correo con el cuerpo cortado
    /// en el primer espacio, que es peor porque nadie lo nota.
    ///
    /// Deliberadamente NO mete el mail ni el id de la cuenta en la URL: el
    /// remitente ya viaja en el mensaje, y meter datos personales en query
    /// params es la clase de cosa que después aparece en un log.
    static func mailURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

// MARK: - Fila reutilizable

/// La tarjeta-fila de esta sección. Es una vista y no un método privado
/// porque la usa también `LegalAndHelpProfileRow`, que vive fuera de la
/// pantalla.
struct LegalRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.bpScaled(17)).foregroundStyle(Color.bpAmber).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                Text(subtitle).font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpTextTertiary)
        }
        .padding(16)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
    }
}

/// La entrada a esta sección. Vive acá y no en `ProfileView` (que ya pasa
/// las 700 líneas) para que sumar la sección cueste tres líneas allá.
struct LegalAndHelpProfileRow: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NavigationLink {
            LegalAndHelpView()
        } label: {
            LegalRow(icon: "lifepreserver",
                     title: l10n.t("profile.legal.section"),
                     subtitle: l10n.t("profile.legal.section.subtitle"))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("profile.legal.section"),
                         hint: l10n.t("profile.legal.section.subtitle"), isButton: true)
        .padding(.horizontal, BPSpacing.lg)
    }
}

// MARK: - La pantalla

struct LegalAndHelpView: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL

    /// El teléfono no tiene app de correo, o nadie tomó el `mailto:`. Pasa
    /// de verdad (Mail borrado, o sin cuenta configurada). Por eso la
    /// dirección se muestra SIEMPRE como texto y esto sólo agrega la
    /// explicación de por qué no se abrió nada.
    @State private var mailFailed = false
    @State private var copied = false
    @State private var showRules = false

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    contactCard

                    // Las reglas NO se reescriben acá: son las mismas que
                    // alguien acepta antes de publicar (`PostingRulesSheet`,
                    // modo `.reference`, que su autor dejó preparado
                    // justamente para esto). Dos textos de reglas se
                    // desincronizan, y el día que eso pasa uno de los dos
                    // le está mintiendo a alguien.
                    Button {
                        BPHaptics.light()
                        showRules = true
                    } label: {
                        LegalRow(icon: "list.bullet.rectangle",
                                 title: l10n.t("profile.legal.guidelines"),
                                 subtitle: l10n.t("legal.rules.subtitle"))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("profile.legal.guidelines"),
                                     hint: l10n.t("legal.rules.subtitle"), isButton: true)

                    NavigationLink { MutedAuthorsView() } label: {
                        LegalRow(icon: "person.slash",
                                 title: l10n.t("profile.blocked.title"),
                                 subtitle: l10n.t("profile.blocked.subtitle"))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("profile.blocked.title"),
                                     hint: l10n.t("profile.blocked.subtitle"), isButton: true)

                    Link(destination: BarPassSupport.terms) {
                        LegalRow(icon: "doc.text", title: l10n.t("profile.legal.terms"),
                                 subtitle: l10n.t("legal.openInBrowser"))
                    }
                    .bpAccessibility(label: l10n.t("profile.legal.terms"),
                                     hint: l10n.t("legal.openInBrowser"), isButton: true)

                    Link(destination: BarPassSupport.privacy) {
                        LegalRow(icon: "hand.raised", title: l10n.t("profile.legal.privacy"),
                                 subtitle: l10n.t("legal.openInBrowser"))
                    }
                    .bpAccessibility(label: l10n.t("profile.legal.privacy"),
                                     hint: l10n.t("legal.openInBrowser"), isButton: true)

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, BPSpacing.md)
            }
        }
        .navigationTitle(l10n.t("profile.legal.section"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRules) { PostingRulesSheet(mode: .reference) }
    }

    // MARK: Contacto

    /// Reportar una FOTO se hace sobre la foto: ahí el servidor sabe cuál es
    /// y quién la subió, y el teléfono no necesita saberlo. Lo que no tenía
    /// dónde reportarse es todo lo demás —una persona que molesta, un cobro,
    /// una cuenta—, y por eso el segundo botón manda otro asunto.
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("profile.support.title"))
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l10n.t("profile.support.subtitle"))
                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // La dirección, escrita. Aunque no haya app de correo, aunque el
            // botón falle, aunque el revisor la quiera copiar a mano: tiene
            // que poder LEERLA. Un botón que dice "Escribinos" y esconde la
            // dirección no publica ningún contacto.
            Text(BarPassSupport.email)
                .font(.bpScaled(15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bpAmber)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    BPHaptics.medium()
                    openMail(subject: l10n.t("legal.contact.subject"),
                             body: String(format: l10n.t("legal.contact.body"), BarPassSupport.appVersion))
                } label: {
                    Text(l10n.t("legal.contact.write"))
                        .font(.bpScaled(14, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("legal.contact.write"),
                                 hint: l10n.t("profile.support.hint"), isButton: true)

                Button {
                    BPHaptics.light()
                    UIPasteboard.general.string = BarPassSupport.email
                    withAnimation { copied = true }
                } label: {
                    Text(l10n.t(copied ? "legal.contact.copied" : "legal.contact.copy"))
                        .font(.bpScaled(14, weight: .semibold)).foregroundStyle(Color.bpInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.bpInk.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("legal.contact.copy"), isButton: true)
            }

            Button {
                BPHaptics.medium()
                openMail(subject: l10n.t("legal.report.other.subject"),
                         body: String(format: l10n.t("legal.report.other.body"), BarPassSupport.appVersion))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill").font(.bpScaled(13))
                    Text(l10n.t("legal.report.other.cta")).font(.bpScaled(14, weight: .bold))
                }
                .foregroundStyle(Color.bpDanger)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.bpDanger.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("legal.report.other.cta"),
                             hint: l10n.t("legal.report.other.subtitle"), isButton: true)

            Text(l10n.t("legal.report.photo.note"))
                .font(.bpScaled(11)).foregroundStyle(Color.bpTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if mailFailed {
                Text(l10n.t("legal.contact.noMailApp"))
                    .font(.bpScaled(12)).foregroundStyle(Color.bpDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
    }

    /// `openURL` con completion en vez de `canOpenURL`: `canOpenURL` sobre
    /// `mailto:` contesta según los esquemas declarados y puede decir que sí
    /// y después no abrir nada. El completion dice qué pasó de verdad.
    private func openMail(subject: String, body: String) {
        guard let url = BarPassSupport.mailURL(subject: subject, body: body) else {
            mailFailed = true
            return
        }
        openURL(url) { accepted in
            mailFailed = !accepted
            if !accepted { BPHaptics.error() }
        }
    }
}
