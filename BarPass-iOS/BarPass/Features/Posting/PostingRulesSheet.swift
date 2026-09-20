import SwiftUI

/// Las reglas, en una pantalla, con una aceptación explícita.
///
/// Dos modos, mismo texto — porque son el mismo texto. `.gate` es la
/// primera vez de cada cuenta y termina en un botón que dice "Acepto";
/// `.reference` es el mismo contenido alcanzable después desde la pantalla
/// de subida (y desde Perfil, si el agente de Perfil lo engancha: esta
/// vista no depende de nada de Tonight y se puede presentar desde
/// cualquier lado con `PostingRulesSheet(mode: .reference)`).
///
/// Lo que va arriba de todo NO son las prohibiciones: es que la foto es
/// pública. Las prohibiciones le importan a Apple; que sea pública le
/// importa a la persona que está por subirla, y es lo único de esta
/// pantalla que hoy la app no dice en ningún otro lado.
struct PostingRulesSheet: View {
    enum Mode { case gate, reference }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    // No hay callback de "aceptó / no aceptó" a propósito: la única marca
    // es la que queda en `PostingRules`, y quien presentó la hoja la vuelve
    // a leer al cerrarse. Un booleano viajando por un closure y una marca
    // persistida son dos fuentes de verdad que se pueden separar — y la que
    // manda tiene que ser la que sobrevive al relanzamiento.

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: BPSpacing.lg) {
                            publicNotice
                            rulesList
                            consequence
                        }
                        .padding(BPSpacing.lg)
                    }
                    actions
                }
            }
            .navigationTitle(l10n.t(mode == .gate ? "posting.rules.title" : "posting.rules.title.reference"))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Empieza grande: estas reglas existen para ser leídas, y una hoja
        // a media pantalla con scroll invita a saltearlas. Se puede bajar
        // a `.medium` para volver a mirar la foto de atrás en `.reference`.
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        // Sólo en `.gate`: arrastrar para cerrar es ambiguo (¿aceptó?), y
        // acá hay un "Ahora no" explícito al lado del "Acepto".
        .interactiveDismissDisabled(mode == .gate)
    }

    // MARK: - Que es pública

    private var publicNotice: some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            HStack(spacing: BPSpacing.sm) {
                Image(systemName: "globe")
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(Color.bpAmber)
                Text(l10n.t("posting.public.title"))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.t("posting.public.detail"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Dicho aparte porque es la otra mitad de la verdad y sin ella
            // la de arriba asusta de más: la foto es pública, el nombre no
            // viaja con ella. `venue_media.user_id` está revocado para
            // `anon` y para `authenticated` (supabase/venue_stories.sql),
            // así que ningún cliente puede saber quién subió qué.
            Text(l10n.t("posting.public.anonymous"))
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BPSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BPRadius.lg)
                .strokeBorder(Color.bpAmber.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Las reglas

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            Text(l10n.t("posting.rules.heading"))
                .font(.bpHeadline())
                .foregroundStyle(Color.bpInk)
                .accessibilityAddTraits(.isHeader)
            ForEach(PostingRules.all) { rule in
                HStack(alignment: .top, spacing: BPSpacing.sm) {
                    Image(systemName: rule.symbol)
                        .font(.bpScaled(15, weight: .semibold))
                        .foregroundStyle(Color.bpDanger)
                        // Ancho fijo para que las cinco líneas de texto
                        // arranquen alineadas con símbolos de distinto ancho.
                        .frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(l10n.t(rule.key))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpInk)
                        // Una regla truncada es una regla que no se aceptó.
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var consequence: some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            Text(l10n.t("posting.rules.consequence"))
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .fixedSize(horizontal: false, vertical: true)
            // Cierra el círculo con la moderación que ya existe: el que
            // acepta las reglas es también el que va a ver una foto que las
            // rompe, y tiene que saber que el botón de reportar existe.
            Text(l10n.t("posting.rules.report"))
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Botones

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: BPSpacing.sm) {
            Button {
                // Aceptar es un compromiso y se siente distinto de cerrar
                // una pantalla que alguien fue a leer por su cuenta.
                if mode == .gate { BPHaptics.success() } else { BPHaptics.light() }
                // Sólo `.gate` escribe. En `.reference` el botón dice
                // "Cerrar" y no puede convertir una lectura en una
                // aceptación que nadie dio.
                if mode == .gate { PostingRules.accept(PostingRules.accountId()) }
                dismiss()
            } label: {
                Text(l10n.t(mode == .gate ? "posting.rules.accept" : "posting.rules.close"))
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
            }
            .buttonStyle(.plain)
            .bpAccessibility(
                label: l10n.t(mode == .gate ? "posting.rules.accept" : "posting.rules.close"),
                hint: mode == .gate ? l10n.t("posting.rules.accept.hint") : "",
                isButton: true
            )

            if mode == .gate {
                Button {
                    BPHaptics.light()
                    dismiss()
                } label: {
                    Text(l10n.t("posting.rules.decline"))
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.bottom, BPSpacing.md)
        .padding(.top, BPSpacing.sm)
        // Fuera del ScrollView: con texto de accesibilidad grande las
        // reglas ocupan más que la pantalla, y el botón de aceptar no
        // puede quedar a tres scrolls de distancia.
        .background(.ultraThinMaterial)
    }
}
