import SwiftUI

/// El acceso al faro desde cualquier pantalla de la app.
///
/// POR QUÉ FLOTA Y NO VIVE ADENTRO DE UN PLAN. La persona que lo necesita
/// está a oscuras, con ruido, probablemente tomada, y buscando con una mano
/// sola. Tres toques para llegar es no llegar. Mismo lugar y mismo tamaño
/// que el botón de irse a casa (GoHomeButton), que resolvió el mismo
/// problema para el mismo momento de la noche.
///
/// CUÁNDO APARECE — dos condiciones, y la segunda es la que importa:
///  · estás con check-in abierto en un lugar: podés levantar la mano.
///  · alguien de tu gente YA levantó la mano: aparece aunque vos no hayas
///    hecho check-in, porque si no, la persona que te está buscando depende
///    de que vos hayas tocado un botón antes. Esa dependencia no puede
///    existir.
/// Fuera de esos dos casos no se muestra: un faro sin audiencia no tiene a
/// quién avisarle, y un botón que sólo puede fallar es peor que ninguno.
struct FindMyGroupButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyBeaconStore.shared
    let isCheckedIn: Bool

    @State private var isPresented = false

    /// Un faro ajeno vivo. El propio no cuenta acá: para ese, lo que hay que
    /// mostrar es el color, y de eso se encarga la pantalla que se abre.
    private var someoneIsLooking: Bool {
        store.incoming.contains { !$0.isResolved }
    }

    private var shouldShow: Bool { isCheckedIn || someoneIsLooking || store.mine != nil }

    var body: some View {
        Group {
            if shouldShow {
                Button {
                    BPHaptics.light()
                    isPresented = true
                } label: {
                    ZStack {
                        Image(systemName: someoneIsLooking ? "hand.raised.fill" : "person.2.fill")
                            .font(.bpScaled(14, weight: .semibold))
                            // Ámbar cuando alguien te está buscando: es la
                            // única condición de la app que justifica pedir
                            // la atención del usuario sin que él haya tocado
                            // nada. Fuera de eso, igual que sus vecinos.
                            .foregroundStyle(someoneIsLooking ? Color.black : Color.bpInk)
                    }
                    .frame(width: 34, height: 34)
                    .background(
                        someoneIsLooking ? AnyShapeStyle(Color.bpAmber)
                                         : AnyShapeStyle(Color.bpCardBackground.opacity(0.97)),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .bpAccessibility(
                    label: l10n.t(someoneIsLooking ? "safety.entry.someoneLooking" : "safety.entry.title"),
                    hint: l10n.t("safety.entry.hint"),
                    isButton: true
                )
            }
        }
        .sheet(isPresented: $isPresented) {
            FindMyGroupView()
        }
        // El store sigue corriendo aunque esta pantalla no esté: el botón
        // sólo puede saber que alguien lo busca si alguien está preguntando.
        .onAppear { store.start() }
    }
}
