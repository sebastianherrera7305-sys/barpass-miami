import SwiftUI
import UIKit

/// Presenta la cubierta a pantalla completa (radar, punto de encuentro) desde el controlador
/// de vista MÁS ALTO de UIKit, no desde un `.fullScreenCover` de SwiftUI.
///
/// POR QUÉ NO `.fullScreenCover` EN `RootView`. Una presentación de SwiftUI
/// cuelga de la vista que la declara, y UIKit sólo deja presentar UNA cosa a
/// la vez desde cada controlador. Si ya hay un `.sheet` abierto por debajo —el
/// grupo, el feed del faro, el carrito— la cubierta de `RootView` se ignora
/// EN SILENCIO: la persona toca "Buscar al líder" y no pasa nada. Es el
/// mismo choque que hizo que el radar del faro viviera adentro de un sheet
/// propio. Presentar desde el controlador más alto no depende de qué haya
/// abierto debajo: la cubierta sube encima de todo, y al cerrarse la persona
/// vuelve exactamente a donde estaba.
///
/// No hay estado propio más que "el controlador que presenté": la verdad es
/// `SafetyPushRouter.isCoverPresented`, que llama a `update(isPresented:)` cada
/// vez que cambia.
@MainActor
final class SafetyCoverPresenter {
    static let shared = SafetyCoverPresenter()

    private var controller: UIViewController?
    private var retry: Task<Void, Never>?

    private init() {}

    func update(isPresented: Bool) {
        if isPresented { present() } else { dismiss() }
    }

    // MARK: Present

    private func present(attempt: Int = 0) {
        guard controller == nil else { return }
        guard let top = Self.topViewController() else { return }

        // Un controlador en plena transición (un sheet que se está yendo, una
        // alerta) rechaza `present`. Se espera un instante y se reintenta, en
        // vez de perder la petición.
        // `presentedViewController != nil` acá sólo puede ser algo que se está
        // yendo (el recorrido de `topViewController` ya lo salteó): el caso de
        // cerrar un radar y abrir otro en el mismo instante.
        if top.isBeingPresented || top.isBeingDismissed || top.isMovingFromParent
            || top.presentedViewController != nil {
            guard attempt < 4 else { return }
            retry?.cancel()
            retry = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.present(attempt: attempt + 1)
            }
            return
        }

        let host = UIHostingController(rootView: SafetyCoverRoot())
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = .black
        controller = host
        top.present(host, animated: true)
    }

    // MARK: Dismiss

    private func dismiss() {
        retry?.cancel()
        retry = nil
        guard let host = controller else { return }
        controller = nil
        // Descarta la cubierta Y lo que se haya presentado encima de ella (el
        // sheet del radar del faro).
        host.presentingViewController?.dismiss(animated: true)
    }

    // MARK: Top-most controller

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// La raíz de la cubierta. Un `UIHostingController` presentado por separado NO
/// hereda los modificadores de `BarPassApp`, así que el esquema de color se
/// vuelve a aplicar acá con la misma regla que usa la app.
struct SafetyCoverRoot: View {
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        SafetyCoverHost()
            .preferredColorScheme(appearance.appearance == .dark ? .dark : .light)
    }
}
