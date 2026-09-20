import SwiftUI

/// The two actions that fire straight from the menu, with no second screen
/// to host their own error. Reporting is not here: it owns a sheet
/// (`ReportSheet`) and therefore owns its own failure message.
enum StoryModerationAction {
    case hide
    case block
}

/// Every frame this device must stop showing, right now.
///
/// It exists because the disappearance has to beat the network. Someone who
/// just reported a photo of themselves cannot be made to watch it for the
/// 12 seconds a contended club LTE takes to answer — so the id goes in here
/// the instant the button is pressed, and comes back out only if the server
/// refuses.
///
/// It is shared rather than per-view because the same frame is rendered in
/// three places (the full-screen viewer, `VenueStoriesStrip`, the Social
/// rail). Hiding it in one and leaving it in the other two would be a bug
/// the user reads as "the report didn't work". Integration is one line at
/// each render site:
///
///     stories.filter { !StoryModerationStore.shared.isSuppressed($0.id) }
///
/// Este conjunto es en memoria y es sólo la cabeza optimista. Lo que
/// persiste depende de la acción, y no son lo mismo:
///  · ocultar → `HiddenStories`, en este teléfono, porque es una preferencia
///    y el servidor no tiene por qué saberla;
///  · silenciar al autor y reportar → el servidor, que los aplica al leer.
/// Después de un relanzamiento, las tres siguen aplicadas: el repositorio
/// filtra las ocultas y las vistas ya vienen filtradas por el servidor.
@MainActor
final class StoryModerationStore: ObservableObject {
    static let shared = StoryModerationStore()

    @Published private(set) var suppressed: Set<String> = []
    /// Set only when an action was rolled back. Rendered by
    /// `.storyModerationFailureAlert()`, attached high enough in the
    /// hierarchy to outlive the viewer that started the action.
    @Published var failure: StoryModerationAction?

    private init() {}

    func isSuppressed(_ mediaId: String) -> Bool { suppressed.contains(mediaId) }

    func suppress(_ mediaId: String) {
        withAnimation(.easeOut(duration: 0.18)) { _ = suppressed.insert(mediaId) }
    }

    func restore(_ mediaId: String) {
        withAnimation(.easeIn(duration: 0.18)) { _ = suppressed.remove(mediaId) }
    }

    /// Optimistic, then honest: the frame goes immediately, and if the call
    /// fails it comes back and we say so. The one thing never done here is
    /// swallowing the error — a silent `try?` would leave the user believing
    /// they had blocked someone they had not.
    func run(_ action: StoryModerationAction, on mediaId: String) {
        suppress(mediaId)
        if action == .hide { HiddenStories.hide(mediaId) }
        Task {
            do {
                switch action {
                // Ocultar es una preferencia de este teléfono: no viaja, no
                // acusa a nadie, y por lo tanto no puede fallar. Se persiste
                // antes de la Task para que sobreviva aunque la vista muera.
                case .hide:  break
                // "Bloquear" es silenciar al AUTOR, direccionado por el id de
                // la foto. El repositorio nunca aprende quién es, y por eso
                // esto no escribe en `user_blocks`: esa tabla la puede leer
                // su dueño, así que bloquear a un desconocido le devolvería
                // su uuid por la puerta de atrás.
                case .block: try await RepositoryDependencies.mediaReport.muteAuthor(ofMediaId: mediaId)
                }
            } catch {
                restore(mediaId)
                failure = action
                BPHaptics.error()
            }
        }
    }
}

/// The way out of a story, on the story itself.
///
/// A visible glyph, not a hidden long-press: press-and-hold on this screen
/// already means "pause so I can read the frame" (`StoryViewer.tapTargets`),
/// and the one control a distressed person must find on the first try is the
/// worst possible place to stack a second meaning onto a gesture. It sits in
/// the header next to the close button, inside the scrim that is already
/// darkening the top of the photo, so it costs the image nothing.
///
/// Opening any of its surfaces pauses playback through `isPaused` — a story
/// that keeps advancing while you decide what to report is a story where you
/// report the wrong frame.
///
/// INTEGRATION: in `StoryViewer`'s ZStack, the header must be layered ABOVE
/// `tapTargets`; that layer is a full-screen `Color.clear` with tap gestures
/// and will otherwise swallow taps meant for this button. Pass the viewer's
/// own `isPaused` as the binding.
struct StoryModerationMenu: View {
    let mediaId: String
    /// Your own frame has nothing to report or block. Deleting it is a
    /// different action with a different owner, so this renders nothing.
    var isMine: Bool = false
    @Binding var isPaused: Bool
    /// Called once the frame is gone and the user is done, so a viewer that
    /// does not filter on the store can still advance past it.
    var onSuppressed: () -> Void = {}

    @ObservedObject private var l10n = L10n.shared
    @State private var showActions = false
    @State private var showBlockConfirm = false
    @State private var showReport = false

    var body: some View {
        if !isMine {
            button
                .confirmationDialog(l10n.t("story.mod.title"), isPresented: $showActions, titleVisibility: .visible) {
                    // Report first: it is why this menu exists. Hide last,
                    // because it is the one choice nobody regrets.
                    Button(l10n.t("story.mod.report"), role: .destructive) { openReport() }
                    Button(l10n.t("story.mod.block"), role: .destructive) { openBlockConfirm() }
                    Button(l10n.t("story.mod.hide")) { hide() }
                    Button(l10n.t("story.mod.cancel"), role: .cancel) { release() }
                }
                .confirmationDialog(
                    l10n.t("story.mod.block.title"),
                    isPresented: $showBlockConfirm,
                    titleVisibility: .visible
                ) {
                    Button(l10n.t("story.mod.block.confirm"), role: .destructive) { block() }
                    Button(l10n.t("story.mod.cancel"), role: .cancel) { release() }
                } message: {
                    // Says what it does, and does not claim it can be undone
                    // from here — there is no unblock in this flow.
                    Text(l10n.t("story.mod.block.body"))
                }
                .sheet(isPresented: $showReport, onDismiss: release) {
                    ReportSheet(mediaId: mediaId)
                }
        }
    }

    private var button: some View {
        Button {
            BPHaptics.light()
            isPaused = true
            showActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.bpScaled(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .bpAccessibility(
            label: l10n.t("story.mod.menu"),
            hint: l10n.t("story.mod.menu.hint"),
            isButton: true
        )
    }

    // MARK: - Actions

    private func openReport() {
        isPaused = true
        showReport = true
    }

    private func openBlockConfirm() {
        isPaused = true
        showBlockConfirm = true
    }

    private func hide() {
        BPHaptics.medium()
        StoryModerationStore.shared.run(.hide, on: mediaId)
        announce(l10n.t("story.mod.hidden.a11y"))
        finish()
    }

    private func block() {
        BPHaptics.heavy()
        StoryModerationStore.shared.run(.block, on: mediaId)
        announce(l10n.t("story.mod.blocked.a11y"))
        finish()
    }

    /// The frame is gone; hand control back to whoever is showing the night.
    private func finish() {
        isPaused = false
        onSuppressed()
    }

    /// Nothing happened — resume the clock we stopped.
    private func release() {
        isPaused = false
    }

    /// The frame vanishes without a word otherwise, which for a VoiceOver
    /// user is indistinguishable from the app freezing.
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

extension View {
    /// Attach once, above the story viewer (RootView is the right height),
    /// so a rolled-back action can still be reported after the viewer that
    /// started it has closed.
    func storyModerationFailureAlert() -> some View {
        modifier(StoryModerationFailureAlert())
    }
}

private struct StoryModerationFailureAlert: ViewModifier {
    @ObservedObject private var store = StoryModerationStore.shared
    @ObservedObject private var l10n = L10n.shared

    func body(content: Content) -> some View {
        content.alert(
            l10n.t("story.mod.failed.title"),
            isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })
        ) {
            Button(l10n.t("story.mod.failed.ok"), role: .cancel) { store.failure = nil }
        } message: {
            Text(l10n.t(store.failure == .block ? "story.mod.failed.block" : "story.mod.failed.hide"))
        }
    }
}
