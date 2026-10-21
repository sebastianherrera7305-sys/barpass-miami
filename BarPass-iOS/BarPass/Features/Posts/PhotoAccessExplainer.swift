import SwiftUI
import PhotosUI

/// Pre-permission explainer for the iOS photo library picker.
///
/// Build 128 TestFlight: testers tapped "Elegí una foto" in the post
/// composer and iOS's own "Private Access to Photos" callout popped
/// with no context from the app. Multiple comments read as the app
/// hitting a wall ("it never ask me", "It's not letting me upload the
/// pictures"). Apple's App Store review guidance is explicit: the
/// system permission UI must be preceded by in-app context in the
/// app's own voice — otherwise it reads as a trap.
///
/// This sheet sits between tapping the picker's entry button and the
/// system prompt. Shown ONCE per account per intent, not per launch:
/// iOS caches the user's answer to the real prompt, and showing our
/// own screen on every subsequent open would be exactly the friction
/// testers complained about. The `PublicPostNotice` (shown on each
/// upload separately) still reminds that the picked photo is public —
/// different responsibility, same screen.
@MainActor
struct PhotoAccessExplainerSheet: View {
    enum Intent: String, Sendable {
        case post        // user's own feed post (PostComposerView)
        case venueMedia  // posting to a venue page / check-in moment
        case tripCover   // trip cover image
        case avatar      // profile avatar photo (future)
    }

    let intent: Intent
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.bpAmber)
                .padding(.bottom, 14)

            Text(titleText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            Text(messageText)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 12) {
                bullet(
                    title: "Acceso completo",
                    detail: "iOS te deja elegir cualquier foto. BarPass sólo ve la que subís."
                )
                bullet(
                    title: "Acceso limitado",
                    detail: "Elegís qué fotos puede ver BarPass. También funciona."
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)

            Button {
                BPHaptics.light()
                PhotoAccessExplainerSheet.markSeen(intent)
                onContinue()
            } label: {
                Text("Continuar")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button {
                onCancel()
            } label: {
                Text("Ahora no")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bpSurface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    private var titleText: String { "Acceso a tus fotos" }

    private var messageText: String {
        switch intent {
        case .post:
            return "Para subir una foto a tu feed necesitamos acceso a tu biblioteca. En un segundo iOS te va a preguntar — podés darnos acceso completo o elegir sólo las fotos que quieras compartir."
        case .venueMedia:
            return "Para subir una foto a este venue necesitamos acceso a tu biblioteca. En un segundo iOS te va a preguntar — podés darnos acceso completo o elegir sólo las fotos que quieras compartir."
        case .tripCover:
            return "Para elegir una portada de la trip necesitamos acceso a tu biblioteca. En un segundo iOS te va a preguntar — podés darnos acceso completo o elegir sólo las fotos que quieras compartir."
        case .avatar:
            return "Para elegir tu foto de perfil necesitamos acceso a tu biblioteca. En un segundo iOS te va a preguntar — podés darnos acceso completo o elegir sólo las fotos que quieras compartir."
        }
    }

    private func bullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Persistence

    private static func key(_ intent: Intent) -> String {
        "bp.photoAccessExplainer.seen.\(intent.rawValue)"
    }

    static func hasSeen(_ intent: Intent) -> Bool {
        UserDefaults.standard.bool(forKey: key(intent))
    }

    static func markSeen(_ intent: Intent) {
        UserDefaults.standard.set(true, forKey: key(intent))
    }
}

/// A ViewModifier that wraps a `.photosPicker(isPresented:…)` with a
/// one-time pre-permission explainer. The caller flips `requestOpen` to
/// true to begin: the first time per intent, we show the sheet; after
/// the user accepts, we open the picker; subsequent calls (same intent,
/// same account) skip straight to the picker.
///
/// Keeping the two sheets on separate booleans with a short delay
/// between them is deliberate: SwiftUI's sheet presentation does not
/// enjoy two sheets flipping in the same run loop tick, and attaching
/// `.photosPicker` to a view that is itself inside a `.sheet` on the
/// same component produces a picker that silently never opens.
@MainActor
struct PhotoAccessGate: ViewModifier {
    @Binding var requestOpen: Bool
    let intent: PhotoAccessExplainerSheet.Intent
    @Binding var showsPicker: Bool

    @State private var showsExplainer = false

    func body(content: Content) -> some View {
        // Capture the two bindings explicitly for the sheet's closures so
        // the deferred `DispatchQueue.main.asyncAfter` call writes through
        // the live source of truth even if the ViewModifier value gets
        // re-created in between.
        let pickerBinding = $showsPicker
        let explainerBinding = $showsExplainer
        return content
            .onChange(of: requestOpen) { _, want in
                guard want else { return }
                requestOpen = false
                if PhotoAccessExplainerSheet.hasSeen(intent) {
                    showsPicker = true
                } else {
                    showsExplainer = true
                }
            }
            .sheet(isPresented: $showsExplainer) {
                PhotoAccessExplainerSheet(
                    intent: intent,
                    onContinue: {
                        explainerBinding.wrappedValue = false
                        // Short gap so SwiftUI finishes dismissing this
                        // sheet before the photosPicker binding flips —
                        // two sheets flipping in the same run-loop tick
                        // leaves the picker silently un-presented.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            pickerBinding.wrappedValue = true
                        }
                    },
                    onCancel: {
                        explainerBinding.wrappedValue = false
                    }
                )
            }
    }
}

extension View {
    /// Insert a one-time pre-permission explainer between a tap on the
    /// picker's entry control and the system "Private Access to Photos"
    /// prompt. Flip `requestOpen` to true from the entry control; the
    /// modifier picks the right next step (explainer or picker).
    @MainActor
    func photoAccessGate(
        requestOpen: Binding<Bool>,
        intent: PhotoAccessExplainerSheet.Intent,
        showsPicker: Binding<Bool>
    ) -> some View {
        modifier(PhotoAccessGate(
            requestOpen: requestOpen,
            intent: intent,
            showsPicker: showsPicker
        ))
    }
}
