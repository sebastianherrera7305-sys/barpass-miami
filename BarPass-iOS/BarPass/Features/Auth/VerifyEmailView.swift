import SwiftUI

/// Full-screen gate shown right after signup/sign-in when the account's
/// email hasn't been confirmed yet. Blocks forward progress — same pattern
/// as AgeGateView — until Supabase reports `email_confirmed_at` is set.
struct VerifyEmailView: View {
    let onVerified: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState

    @State private var isChecking     = false
    @State private var isResending    = false
    @State private var resendCooldown = 0
    @State private var statusMessage  = ""
    @State private var isError        = false
    @State private var pollTask: Task<Void, Never>?

    private var email: String { AuthService.shared.restoreSession()?.user.email ?? "" }

    var body: some View {
        ZStack {
            BPBackgroundView()

            VStack(spacing: 28) {
                Spacer()

                BarPassLogo(subtitle: nil)

                VStack(spacing: 20) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.bpAmber)

                    Text(l10n.t("verifyEmail.title"))
                        .font(.bpTitle1())
                        .foregroundStyle(Color.bpInk)
                        .multilineTextAlignment(.center)

                    Text(String(format: l10n.t("verifyEmail.subtitle"), email))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.bpCaption())
                            .foregroundStyle(isError ? Color.bpDanger : Color.bpGreen)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    Button {
                        checkVerification()
                    } label: {
                        HStack(spacing: 8) {
                            if isChecking {
                                ProgressView().tint(.black)
                            }
                            Text(l10n.t("verifyEmail.iVerified"))
                        }
                        .font(.bpScaled(17, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecking)
                    .bpAccessibility(label: l10n.t("verifyEmail.iVerified"), hint: l10n.t("verifyEmail.iVerified.hint"), isButton: true)

                    Button {
                        resend()
                    } label: {
                        Text(resendCooldown > 0
                             ? String(format: l10n.t("verifyEmail.resendCooldown"), resendCooldown)
                             : l10n.t("verifyEmail.resend"))
                            .font(.bpScaled(14, weight: .semibold))
                            .foregroundStyle(resendCooldown > 0 || isResending ? Color.bpTextTertiary : Color.bpAmber)
                    }
                    .buttonStyle(.plain)
                    .disabled(isResending || resendCooldown > 0)
                    .bpAccessibility(label: l10n.t("verifyEmail.resend"), hint: l10n.t("verifyEmail.resend.hint"), isButton: true)

                    Button {
                        pollTask?.cancel()
                        AuthService.shared.signOut()
                        appState.showEmailVerification = false
                        appState.showNativeAuth = true
                    } label: {
                        Text(l10n.t("verifyEmail.signOut"))
                            .font(.bpScaled(13, weight: .semibold))
                            .foregroundStyle(Color.bpTextSecondary)
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("verifyEmail.signOut"), hint: l10n.t("verifyEmail.signOut.hint"), isButton: true)
                }
                .animation(.easeInOut(duration: 0.2), value: statusMessage)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Polling (auto-detect verification without a manual tap)

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                if let session = try? await AuthService.shared.refreshUserStatus(), session.isEmailVerified {
                    await MainActor.run {
                        BPHaptics.success()
                        onVerified()
                    }
                    return
                }
            }
        }
    }

    // MARK: - Actions

    private func checkVerification() {
        guard !isChecking else { return }
        isChecking = true
        isError = false
        Task {
            do {
                let session = try await AuthService.shared.refreshUserStatus()
                await MainActor.run {
                    isChecking = false
                    if session.isEmailVerified {
                        pollTask?.cancel()
                        BPHaptics.success()
                        onVerified()
                    } else {
                        isError = true
                        statusMessage = l10n.t("verifyEmail.stillNotVerified")
                        BPHaptics.error()
                    }
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    isError = true
                    statusMessage = l10n.t("auth.error.connection")
                }
            }
        }
    }

    private func resend() {
        guard !isResending, resendCooldown == 0, !email.isEmpty else { return }
        isResending = true
        Task {
            do {
                try await AuthService.shared.resendVerificationEmail(email: email)
                await MainActor.run {
                    isResending = false
                    isError = false
                    statusMessage = l10n.t("verifyEmail.resent")
                    startCooldown()
                }
            } catch {
                await MainActor.run {
                    isResending = false
                    isError = true
                    statusMessage = l10n.t("verifyEmail.resendError")
                }
            }
        }
    }

    private func startCooldown() {
        resendCooldown = 30
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { resendCooldown = max(0, resendCooldown - 1) }
            }
        }
    }
}

#Preview {
    VerifyEmailView(onVerified: {})
        .environmentObject(AppState())
}
