import SwiftUI
import PhotosUI

/// El botón de subir, con las reglas adelante la primera vez.
///
/// Reemplaza al `PhotosPicker` que estaba directo en las dos pantallas de
/// subida (`VenueMediaSection`, `CheckInMomentSheet`). La compuerta va
/// ANTES de elegir la foto y no después: quien ya eligió la foto de la
/// noche ya decidió, y unas reglas que aparecen en ese momento se leen
/// como un trámite entre la persona y el botón. Antes de abrir la galería
/// todavía son información.
///
/// Una sola vez por cuenta (`PostingRules`). Después, el botón abre la
/// galería directo — preguntar en cada subida entrena a tocar "Acepto"
/// sin leer, que es la forma más rápida de que unas reglas dejen de
/// significar nada. El texto queda alcanzable igual desde
/// `PublicPostNotice`, que sí se muestra en cada subida.
struct PostingPickerButton<Label: View>: View {
    @Binding var selection: PhotosPickerItem?
    let isDisabled: Bool
    private let label: () -> Label

    init(
        selection: Binding<PhotosPickerItem?>,
        isDisabled: Bool = false,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self._selection = selection
        self.isDisabled = isDisabled
        self.label = label
    }

    @State private var showPicker = false
    @State private var showRules = false
    /// La cuenta que se estaba mirando al abrir las reglas. Se guarda en
    /// vez de volver a pedirla al cerrar: `restoreSession()` emite un
    /// evento de analytics por llamada, y además así la respuesta al
    /// cerrar la hoja es sobre la misma cuenta que la abrió.
    @State private var pendingAccount: String?

    var body: some View {
        Button {
            BPHaptics.light()
            let account = PostingRules.accountId()
            if PostingRules.hasAccepted(account) {
                showPicker = true
            } else {
                pendingAccount = account
                showRules = true
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .photosPicker(
            isPresented: $showPicker,
            selection: $selection,
            matching: .any(of: [.images, .videos])
        )
        // `onDismiss` relee la marca persistida en vez de recibir un
        // booleano de la hoja: así "aceptó" significa exactamente lo mismo
        // acá que en el próximo lanzamiento de la app, y arrastrar la hoja
        // hacia abajo no puede parecerse a aceptar.
        .sheet(isPresented: $showRules, onDismiss: {
            if PostingRules.hasAccepted(pendingAccount) { showPicker = true }
            pendingAccount = nil
        }) {
            PostingRulesSheet(mode: .gate)
        }
    }
}

/// El recordatorio de que la foto es pública, en cada subida.
///
/// No es decorativo y no se puede reemplazar por "ya lo aceptó una vez":
/// aceptar las reglas pasa una sola vez, y el dato que la persona necesita
/// tener presente cada vez que sube algo es quién lo va a ver. Hoy la app
/// dice "lo ve todo el mundo en la página del lugar"
/// (`checkin.moment.subtitle`), que se puede leer como "todo el mundo que
/// esté en la app" — y no es eso: `venue_media` se lee con rol `anon`
/// (supabase/venue_media.sql), así que se ve sin cuenta.
///
/// Además es la puerta a las reglas después de aceptadas, que es el
/// requisito de que sigan alcanzables desde la pantalla de subida.
struct PublicPostNotice: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var showRules = false

    var body: some View {
        HStack(alignment: .top, spacing: BPSpacing.sm) {
            Image(systemName: "globe")
                .font(.bpScaled(12, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("posting.notice.public"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    // En portugués y en inglés esta línea entra en dos
                    // renglones; truncarla borraría justamente "sin cuenta".
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    BPHaptics.light()
                    showRules = true
                } label: {
                    Text(l10n.t("posting.notice.rules"))
                        .font(.bpScaled(12, weight: .bold))
                        .foregroundStyle(Color.bpAmber)
                        .underline()
                }
                .buttonStyle(.plain)
                .bpAccessibility(
                    label: l10n.t("posting.notice.rules"),
                    hint: l10n.t("posting.notice.rules.hint"),
                    isButton: true
                )
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showRules) {
            PostingRulesSheet(mode: .reference)
        }
    }
}
