import SwiftUI

/// Deshacer lo que bloqueaste y lo que ocultaste.
///
/// POR QUÉ ESTA PANTALLA NO ES UNA LISTA, que es lo primero que se pregunta
/// cualquiera que la abra:
///
/// `MediaReportRepository` se direcciona SIEMPRE por id de media y nunca por
/// id de autor, porque `venue_media.user_id` está revocado para `anon` y para
/// `authenticated` — el teléfono literalmente no sabe quién subió cada foto,
/// y esa invariante es la razón por la que una foto pública no publica además
/// el historial de ubicación de una persona con nombre. De ahí sale todo lo
/// demás: la app no puede pedirle al servidor "dame a quiénes silencié"
/// porque no hay función que lo devuelva, y no hay función que lo devuelva
/// porque devolverla sería devolver uuids de autores.
///
/// Con la API de hoy (`unmuteAuthor(ofMediaId:)` + `clearMutedAuthors()`) lo
/// único que se puede ofrecer honestamente es deshacer TODO junto, y eso es
/// lo que esta pantalla hace. `unmuteAuthor(ofMediaId:)` existe pero no tiene
/// cómo llamarse desde acá: para apuntar a un silenciamiento hace falta una
/// foto de ese autor, y las historias vencen a las 6 AM.
///
/// LO QUE HARÍA FALTA DEL LADO DEL SERVIDOR para que esto sí sea una lista —y
/// no se inventa acá, se pide— es una RPC `security definer` tipo
/// `list_my_media_author_mutes()` que devuelva, por cada silenciamiento, un
/// HANDLE OPACO Y POR-ESPECTADOR (no el uuid del autor: un hash con sal del
/// par silenciador+autor, estable sólo para este usuario), la fecha, y a lo
/// sumo el venue donde pasó; más una `unmute_by_handle(p_handle text)`. Así
/// la lista se puede mostrar y deshacer una por una sin que el cliente
/// aprenda nunca quién es nadie. Mientras eso no exista, esta pantalla dice
/// la verdad en vez de simular una lista vacía.
struct MutedAuthorsView: View {
    @ObservedObject private var l10n = L10n.shared

    @State private var isClearing = false
    @State private var clearedMutes = false
    @State private var errorText: String?
    @State private var showConfirm = false
    /// Las fotos ocultas viven en este teléfono (`HiddenStories`), así que
    /// esto sí se puede contar y sí se puede deshacer una por una — es el
    /// único lado de la pantalla que tiene números reales.
    @State private var hiddenCount = HiddenStories.all().count

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    mutedCard
                    hiddenCard
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, BPSpacing.md)
            }
        }
        .navigationTitle(l10n.t("profile.blocked.title"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(l10n.t("legal.muted.confirm.title"),
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button(l10n.t("legal.muted.confirm.cta")) { clearMutes() }
            Button(l10n.t("media.report.cancel"), role: .cancel) {}
        } message: {
            Text(l10n.t("legal.muted.confirm.body"))
        }
    }

    // MARK: - Silenciados en el servidor

    private var mutedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("legal.muted.why.title"))
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l10n.t("legal.muted.why.body"))
                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                BPHaptics.light()
                showConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isClearing { ProgressView().tint(Color.bpInk) }
                    Text(l10n.t("media.report.muteAuthor.clearAll"))
                        .font(.bpScaled(14, weight: .bold))
                }
                .foregroundStyle(Color.bpInk)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.bpInk.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isClearing)
            .bpAccessibility(label: l10n.t("media.report.muteAuthor.clearAll"),
                             hint: l10n.t("legal.muted.clearAll.hint"), isButton: true)

            // El resultado, dicho. Un botón que se apaga y no dice nada deja
            // a la persona sin saber si deshizo algo o si falló en silencio.
            if clearedMutes {
                Text(l10n.t("legal.muted.done"))
                    .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorText {
                Text(errorText)
                    .font(.bpScaled(12)).foregroundStyle(Color.bpDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
    }

    private func clearMutes() {
        isClearing = true
        errorText = nil
        clearedMutes = false
        Task {
            do {
                try await RepositoryDependencies.mediaReport.clearMutedAuthors()
                isClearing = false
                clearedMutes = true
                BPHaptics.success()
            } catch {
                isClearing = false
                // `MediaReportError` ya trae su texto traducido (sesión
                // vencida, sin señal); cualquier otro error cae en el
                // genérico en vez de mostrar un `localizedDescription` de
                // URLSession en inglés.
                errorText = (error as? MediaReportError)?.errorDescription ?? l10n.t("legal.muted.error")
                BPHaptics.error()
            }
        }
    }

    // MARK: - Ocultas en este teléfono

    private var hiddenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("legal.hidden.title"))
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l10n.t("legal.hidden.body"))
                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if hiddenCount == 0 {
                Text(l10n.t("legal.hidden.none"))
                    .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpTextTertiary)
            } else {
                Text(String(format: l10n.t("legal.hidden.count"), hiddenCount))
                    .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpInk)

                Button {
                    BPHaptics.medium()
                    unhideAll()
                } label: {
                    Text(l10n.t("legal.hidden.showAll"))
                        .font(.bpScaled(14, weight: .bold)).foregroundStyle(Color.bpInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.bpInk.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("legal.hidden.showAll"),
                                 hint: l10n.t("legal.hidden.body"), isButton: true)
            }
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
    }

    /// Una por una y no de un saque porque `HiddenStories` no expone un
    /// "borrar todo" y este archivo no es dueño de ese tipo. El tope duro de
    /// esa lista son 500 ids, así que el costo es irrelevante y se paga una
    /// sola vez, cuando alguien toca el botón.
    ///
    /// El `restore` del store en memoria es lo que hace que el cambio se vea
    /// AHORA: `HiddenStories` lo lee el repositorio en la próxima carga, pero
    /// las historias que ya están en pantalla las filtra
    /// `StoryModerationStore.suppressed`, y una que quedara ahí seguiría
    /// invisible hasta relanzar la app.
    private func unhideAll() {
        for id in HiddenStories.all() {
            HiddenStories.unhide(id)
            StoryModerationStore.shared.restore(id)
        }
        hiddenCount = HiddenStories.all().count
    }
}
