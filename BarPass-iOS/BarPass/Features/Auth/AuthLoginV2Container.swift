import SwiftUI
import AuthenticationServices

/// Thin shell that wires the designer's `AuthLoginV2View` to the live
/// `AuthService`. Keeps the pure-visual view free of backend knowledge so
/// previews/debug menu entries render unchanged, and gives the real flow one
/// place for loading state, error toasts, and the forgot-password sheet.
///
/// Entry points today:
/// - `RootView` when `V2Flags.authV2` is on (default off until we see this
///   render against real Supabase traffic).
/// - The Profile debug menu, so the owner can click through the design
///   against a real staging user.
///
/// Deliberately NOT a replacement for `NativeAuthView` — we gate on a flag
/// so a regression in the V2 layer rolls back to V1 with one UserDefault.
@MainActor
struct AuthLoginV2Container: View {
    @EnvironmentObject private var appState: AppState

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgot = false
    @State private var resetEmail = ""
    @State private var resetError: String?
    @State private var resetSent = false
    /// True until the saved-session check settles. V1 NativeAuthView does
    /// this in onAppear: a returning user with a valid (or refreshable)
    /// session goes straight to completeAuth() and never sees the form.
    /// Without it, V2 showed the login screen on every launch.
    @State private var restoring = true

    var body: some View {
        Group {
            if restoring {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.bpAmber)
                }
            } else {
                loginForm
            }
        }
        .onAppear { restoreSessionIfPossible() }
    }

    private var loginForm: some View {
        AuthLoginV2View(
            onSignIn: { email, password in
                signIn(email: email, password: password)
            },
            onSignUp: { email, password in
                signUp(email: email, password: password)
            },
            onAppleIdToken: { idToken, rawNonce in
                signInWithApple(idToken: idToken, rawNonce: rawNonce)
            },
            onAppleError: { error in
                withAnimation { errorMessage = error.localizedDescription }
            },
            onForgotPassword: {
                resetEmail = ""
                resetError = nil
                resetSent = false
                showForgot = true
            },
            onTerms: {
                openURL("https://barpass-v2.vercel.app/legal/terms")
            },
            onPrivacy: {
                openURL("https://barpass-v2.vercel.app/legal/privacy")
            },
            onGuest: {
                appState.completeAuth()
            },
            isLoading: isLoading,
            errorMessage: errorMessage
        )
        .sheet(isPresented: $showForgot) {
            AuthLoginV2ForgotSheet(
                email: $resetEmail,
                error: $resetError,
                sent: $resetSent
            ) {
                await sendReset()
            }
            .presentationDetents([.height(380)])
            .presentationBackground(.black)
        }
    }

    // MARK: - Launch-time session restore (mirrors NativeAuthView.onAppear)

    private func restoreSessionIfPossible() {
        guard let session = AuthService.shared.restoreSession() else {
            restoring = false
            return
        }
        if !session.isExpired {
            appState.completeAuth()
            return
        }
        // Expired: a decoded session is not proof the refresh token still
        // works server-side. Confirm the refresh before letting the user in,
        // otherwise they would be "signed in" against a dead session.
        Task {
            let refreshed = await AuthService.shared.refreshIfNeeded()
            await MainActor.run {
                if refreshed {
                    appState.completeAuth()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { restoring = false }
                }
            }
        }
    }

    // MARK: - Email / password

    private func signIn(email: String, password: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            withAnimation { errorMessage = "Completa email y contraseña." }
            return
        }
        start()
        Task {
            do {
                _ = try await AuthService.shared.signIn(email: trimmed, password: password)
                await finishSuccess()
            } catch {
                await finishFailure(error)
            }
        }
    }

    private func signUp(email: String, password: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, password.count >= 8 else {
            withAnimation {
                errorMessage = password.count < 8
                    ? "La contraseña necesita al menos 8 caracteres."
                    : "Completa email y contraseña."
            }
            return
        }
        start()
        Task {
            do {
                _ = try await AuthService.shared.signUp(email: trimmed, password: password)
                await finishSuccess()
            } catch {
                await finishFailure(error)
            }
        }
    }

    private func signInWithApple(idToken: String, rawNonce: String) {
        start()
        Task {
            do {
                _ = try await AuthService.shared.signInWithApple(idToken: idToken, nonce: rawNonce)
                await finishSuccess()
            } catch {
                await finishFailure(error)
            }
        }
    }

    private func sendReset() async {
        let trimmed = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetError = "Escribe tu email."
            return
        }
        resetError = nil
        do {
            try await AuthService.shared.sendPasswordReset(email: trimmed)
            await MainActor.run {
                withAnimation { resetSent = true }
            }
        } catch {
            await MainActor.run {
                resetError = error.localizedDescription
            }
        }
    }

    // MARK: - State transitions

    private func start() {
        withAnimation {
            isLoading = true
            errorMessage = nil
        }
    }

    private func finishSuccess() async {
        await MainActor.run {
            isLoading = false
            appState.completeAuth()
        }
    }

    private func finishFailure(_ error: Error) async {
        await MainActor.run {
            withAnimation {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Forgot password sheet (V2-styled)

@MainActor
private struct AuthLoginV2ForgotSheet: View {
    @Binding var email: String
    @Binding var error: String?
    @Binding var sent: Bool
    let onSend: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            if sent {
                sentContent
            } else {
                formContent
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var formContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 28))
                .foregroundStyle(Color.bpAmber)

            Text("¿Olvidaste tu contraseña?")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Te mandamos un link al email para resetearla.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)

            TextField("tu@email.com", text: $email)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.bpDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Cancelar") {
                    dismiss()
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 12))

                Button {
                    busy = true
                    Task {
                        await onSend()
                        busy = false
                    }
                } label: {
                    if busy {
                        ProgressView().tint(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    } else {
                        Text("Mandar")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 12))
                .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var sentContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.bpGreen)

            Text("Revisa tu email")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Te mandamos un link a \(email).")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button("Listo") {
                dismiss()
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
    }
}

#if DEBUG
#Preview("AuthLoginV2Container") {
    AuthLoginV2Container()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
#endif
