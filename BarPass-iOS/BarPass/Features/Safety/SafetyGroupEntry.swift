import SwiftUI

/// La puerta al grupo efímero: un ícono de barra, en Trips (el lugar de los
/// planes con gente). Abre `SafetyGroupView` en un sheet y avisa con un punto
/// cuando alguien de tu grupo te está buscando (sólo el líder lo ve).
///
/// UN DUEÑO POR CONTROL: el botón flotante y la pantalla "Encontrá a tu gente"
/// son del faro y no llevan nada del grupo. Si algún día conviene una sola
/// pantalla, se diseña como una pantalla con dos secciones, no como una fila
/// del grupo insertada en el feed del faro.
struct SafetyGroupEntryButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyGroupStore.shared
    @State private var isPresented = false

    var body: some View {
        Button {
            BPHaptics.light()
            isPresented = true
        } label: {
            Image(systemName: store.group == nil ? "person.3" : "person.3.fill")
                .foregroundStyle(store.incomingSeek == nil ? Color.bpInk : Color.bpAmber)
                .overlay(alignment: .topTrailing) {
                    if store.incomingSeek != nil {
                        Circle().fill(Color.bpDanger).frame(width: 8, height: 8).offset(x: 4, y: -3)
                    }
                }
        }
        .bpAccessibility(label: l10n.t("safetyGroup.entry"), isButton: true)
        .sheet(isPresented: $isPresented) { SafetyGroupView() }
    }
}
