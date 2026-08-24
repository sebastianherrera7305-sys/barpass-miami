import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - Auth Metrics

struct AuthMetrics {
    let validationTime: Double
    let requestTime: Double
    let totalTime: Double
}

// MARK: - Auth Flow State Machine

enum AuthFlowState: Equatable {
    case idle
    case validating
    case signingIn
    case signingUp
    case loadingUser
    case success
    case failure(String)

    var isLoading: Bool {
        switch self {
        case .validating, .signingIn, .signingUp, .loadingUser: return true
        default: return false
        }
    }

    /// l10n key for the current state's button label (empty string = no key).
    /// Resolved with `l10n.t(...)` at the call site, since this enum is not
    /// main-actor isolated but `L10n` is.
    var buttonLabelKey: String {
        switch self {
        case .idle, .validating, .failure: return ""
        case .signingIn:  return "auth.state.signingIn"
        case .signingUp:  return "auth.state.signingUp"
        case .loadingUser: return "auth.state.loadingUser"
        case .success:    return "auth.state.success"
        }
    }
}

// MARK: - View

struct NativeAuthView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState

    // State machine
    @State private var flowState: AuthFlowState = .idle

    // Input fields
    @State private var tab:          AuthTab = .signIn
    @State private var email         = ""
    @State private var password      = ""
    @State private var showPassword  = false

    // Animations
    @State private var contentOpacity: Double  = 0
    @State private var contentY:       CGFloat = 12



    // Forgot password
    @State private var showForgotPassword = false
    @State private var resetEmail         = ""
    @State private var resetStatusMsg     = ""
    @State private var isSendingReset     = false

    // Performance tracking
    @State private var lastMetrics: AuthMetrics?
    @State private var appleNonce = ""

    private let amber  = Color.bpAmber
    private let amberB = Color.bpAmberBright

    enum AuthTab { case signIn, signUp }

    // MARK: - Body

    var body: some View {
        ZStack {
            ComicHalftoneBackground()

            mainContent

            // Session checking overlay
            if flowState == .idle && contentOpacity < 0.5 {
                BarPassLoadingView(size: 56, caption: l10n.t("auth.checkingSession"))
                .transition(.opacity)
            }

            // Error toast at bottom
            if case .failure(let msg) = flowState {
                ErrorToast(
                    message: msg,
                    onDismiss: { withAnimation(.spring(response: 0.3)) { flowState = .idle } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .zIndex(10)
            }
        }
        .onAppear(perform: onAppear)
        .sheet(isPresented: $showForgotPassword) {
            forgotPasswordSheet
                .presentationDetents([.height(340)])
                .presentationBackground(.clear)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: flowState)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()
            logoSection
                .padding(.bottom, 52)

            tabPicker
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            fieldsSection
                .padding(.horizontal, 24)

            if tab == .signIn {
                forgotPasswordLink
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            ctaButton
                .padding(.horizontal, 24)
                .padding(.top, 24)

            legalFooter
                .padding(.horizontal, 24)
                .padding(.top, 14)

            divider
                .padding(.horizontal, 24)
                .padding(.top, 28)

            appleSignInButton
                .padding(.horizontal, 24)
                .padding(.top, 20)

            skipButton
                .padding(.top, 20)

            socialProof
                .padding(.top, 28)

            Spacer()
        }
        .opacity(contentOpacity)
        .offset(y: contentY)
    }

    // MARK: - On Appear

    private func onAppear() {
        // Check session FIRST, synchronously — if found, skip auth entirely
        if AuthService.shared.restoreSession() != nil {
            appState.completeAuth()
            // Silently refresh token in background if needed
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); _ = await AuthService.shared.refreshIfNeeded() }
            return
        }
        flowState = .idle

        // Only animate content in when we're actually showing the form
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            contentOpacity = 1
            contentY       = 0
        }
    }

    // MARK: - Legal footer

    /// NOTE: update these URLs once barpass-v2 is deployed to its final domain.
    private var legalFooter: some View {
        HStack(spacing: 4) {
            Text(l10n.t("auth.legal.prefix"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpInk.opacity(0.35))
            Link(l10n.t("auth.legal.terms"), destination: URL(string: "https://barpass-v2.vercel.app/legal/terms")!)
                .font(.bpScaled(11, weight: .semibold))
                .foregroundStyle(amber)
            Text(l10n.t("auth.legal.and"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpInk.opacity(0.35))
            Link(l10n.t("auth.legal.privacy"), destination: URL(string: "https://barpass-v2.vercel.app/legal/privacy")!)
                .font(.bpScaled(11, weight: .semibold))
                .foregroundStyle(amber)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .bpAccessibility(label: l10n.t("auth.legal.a11y.label"), hint: l10n.t("auth.legal.a11y.hint"))
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                ComicBurstShape()
                    .fill(.white)
                    .overlay(ComicBurstShape().stroke(.black, lineWidth: 3))
                    .frame(width: 108, height: 108)

                Image("BarPassMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 59)
                    .padding(13)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(.black, lineWidth: 4))
            }

            // Sits on the amber panel — black text, not the theme-driven
            // bpInk (which assumes a dark background).
            VStack(spacing: 5) {
                Text("BarPass")
                    .font(.bpScaled(30, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .kerning(-0.4)

                Text(l10n.t("auth.tagline"))
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "BarPass", hint: l10n.t("auth.tagline"))
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabBtn(l10n.t("auth.tab.signIn"),      for: .signIn)
            tabBtn(l10n.t("auth.tab.signUp"), for: .signUp)
        }
    }

    private func tabBtn(_ label: String, for t: AuthTab) -> some View {
        let active = tab == t && !flowState.isLoading
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                tab = t
                flowState = .idle
            }
        } label: {
            // Sits on the black field below the amber panel, not on the
            // panel itself — needs light text, unlike the logo section.
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 15, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(tab == t && !flowState.isLoading ? Color.bpAmber : Color.clear)
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
        .bpAccessibility(
            label: t == .signIn ? l10n.t("auth.tab.signIn.a11y") : l10n.t("auth.tab.signUp.a11y"),
            hint: t == .signIn ? l10n.t("auth.tab.signIn.hint") : l10n.t("auth.tab.signUp.hint"),
            isButton: true
        )
        .animation(.easeInOut(duration: 0.2), value: active)
    }

    // MARK: - Input Fields

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(spacing: 10) {
            if tab == .signUp {
                // Name field is removed — Supabase signup only needs email + password.
                // Profile name can be added later via a profile update screen.
            }
            field(l10n.t("auth.field.email"), text: $email,
                  keyboard: .emailAddress, icon: "envelope", secure: false)
            field(l10n.t("auth.field.password"), text: $password,
                  keyboard: .default, icon: "lock", secure: true)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType, icon: String, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk.opacity(0.28))
                .frame(width: 18)

            Group {
                if secure && !showPassword {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboard)
                        .autocapitalization(keyboard == .emailAddress ? .none : .words)
                        .autocorrectionDisabled()
                }
            }
            .foregroundStyle(Color.bpInk)
            .tint(amber)
            .bpAccessibility(
                label: placeholder == l10n.t("auth.field.email") ? l10n.t("auth.field.email.a11y") : l10n.t("auth.field.password.a11y"),
                hint: placeholder == l10n.t("auth.field.email") ? l10n.t("auth.field.email.hint") : l10n.t("auth.field.password.hint")
            )

            if secure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.bpScaled(13))
                        .foregroundStyle(Color.bpInk.opacity(0.25))
                }
                .buttonStyle(.plain)
                .bpAccessibility(
                    label: showPassword ? l10n.t("auth.hidePassword") : l10n.t("auth.showPassword"),
                    hint: l10n.t("auth.togglePassword.hint"),
                    isButton: true
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 0).strokeBorder(.black, lineWidth: 3))
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        let isDisabled: Bool = {
            switch flowState {
            case .signingIn, .signingUp, .loadingUser: return true
            default: break
            }
            if case .failure = flowState { return false }
            return email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty
        }()

        let label: String = {
            if flowState.isLoading { return l10n.t(flowState.buttonLabelKey) }
            if case .failure = flowState { return l10n.t("auth.tryAgain") }
            return tab == .signIn ? l10n.t("auth.enter") : l10n.t("auth.createAccount")
        }()

        let showSpinner: Bool = {
            switch flowState {
            case .validating, .signingIn, .signingUp, .loadingUser: return true
            default: return false
            }
        }()

        // Pink, not amber — the CTA is a distinct accent from the panel
        // behind it (design canvas "Comic Halftone" direction), so it
        // reads as its own tappable object rather than blending into it.
        let ctaPink = Color(red: 0.949, green: 0.447, blue: 0.565)

        return Button {
            guard !flowState.isLoading else { return }
            submit()
        } label: {
            ZStack {
                Rectangle()
                    .fill(isDisabled ? Color.bpInk.opacity(0.08) : ctaPink)
                    .frame(height: 54)

                HStack(spacing: 8) {
                    if showSpinner {
                        ProgressView()
                            .tint(isDisabled ? Color.bpInk.opacity(0.3) : .black)
                            .scaleEffect(0.85)
                    }
                    Text(label)
                        .font(.bpScaled(17, weight: .black))
                        .foregroundStyle(isDisabled ? Color.bpInk.opacity(0.25) : .black)
                }
            }
        }
        .buttonStyle(.plain)
        .stickerCard(cornerRadius: 0, borderWidth: 4, shadowOffset: isDisabled ? 0 : 6)
        .rotationEffect(.degrees(isDisabled ? 0 : -0.6))
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.18), value: isDisabled)
        .animation(.easeInOut(duration: 0.18), value: label)
        .opacity(flowState.isLoading ? 0.9 : 1)
        .bpAccessibility(
            label: tab == .signIn ? l10n.t("auth.enter") : l10n.t("auth.createAccount"),
            hint: tab == .signIn ? l10n.t("auth.enter.hint") : l10n.t("auth.createAccount.hint"),
            isButton: true
        )
    }

    // MARK: - Divider

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.bpInk.opacity(0.07))
                .frame(height: 1)
            Text(l10n.t("auth.or"))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpInk.opacity(0.2))
            Rectangle()
                .fill(Color.bpInk.opacity(0.07))
                .frame(height: 1)
        }
    }

    // MARK: - Sign in with Apple

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonce()
            appleNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .clipShape(Rectangle())
        .stickerCard(cornerRadius: 0, borderWidth: 3, shadowOffset: 5)
        .disabled(flowState.isLoading)
        .bpAccessibility(label: l10n.t("auth.apple.continue"), hint: l10n.t("auth.apple.hint"), isButton: true)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            // User cancelled the sheet — not a real error, don't show a toast.
            if nsError.code == ASAuthorizationError.canceled.rawValue { return }
            withAnimation { flowState = .failure(error.localizedDescription) }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                withAnimation { flowState = .failure(L10n.shared.t("auth.apple.error")) }
                return
            }
            let nonce = appleNonce
            withAnimation { flowState = .signingIn }
            Task {
                do {
                    _ = try await AuthService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                    await MainActor.run { appState.completeAuth() }
                } catch {
                    await MainActor.run { withAnimation { flowState = .failure(error.localizedDescription) } }
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < chars.count {
                result.append(chars[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Forgot Password

    private var forgotPasswordLink: some View {
        Button {
            resetEmail = email
            showForgotPassword = true
        } label: {
            Text(l10n.t("auth.forgotPassword"))
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
        .frame(maxWidth: .infinity)
        .bpAccessibility(label: l10n.t("auth.forgotPassword.a11y"), hint: l10n.t("auth.forgotPassword.hint"), isButton: true)
    }

    // MARK: - Forgot Password Sheet

    private var forgotPasswordSheet: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.bpInk.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Spacer()

            if resetStatusMsg.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "lock.rotation")
                        .font(.bpScaled(28))
                        .foregroundStyle(Color.bpAmber)

                    Text(l10n.t("auth.reset.title"))
                        .font(.bpTitle2())
                        .foregroundStyle(Color.bpInk)

                    Text(l10n.t("auth.reset.subtitle"))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)

                    TextField(l10n.t("auth.reset.placeholder"), text: $resetEmail)
                        .font(.bpBody())
                        .foregroundStyle(Color.bpInk)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpInk.opacity(0.07)))
                        .bpAccessibility(label: l10n.t("auth.field.email.a11y"), hint: l10n.t("auth.reset.field.hint"))
                }
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 12) {
                    Button(l10n.t("tripCreate.cancel")) {
                        showForgotPassword = false
                        resetStatusMsg = ""
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .bpAccessibility(label: l10n.t("tripCreate.cancel"), hint: l10n.t("auth.reset.cancel.hint"), isButton: true)

                    Button {
                        sendPasswordReset()
                    } label: {
                        Text(l10n.t("auth.reset.send"))
                            .font(.bpHeadline())
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .opacity(resetEmail.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .disabled(resetEmail.trimmingCharacters(in: .whitespaces).isEmpty || isSendingReset)
                    .bpAccessibility(label: l10n.t("auth.reset.send"), hint: l10n.t("auth.reset.send.hint"), isButton: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.bpScaled(48))
                        .foregroundStyle(Color.bpGreen)

                    Text(l10n.t("auth.reset.checkEmail"))
                        .font(.bpTitle2())
                        .foregroundStyle(Color.bpInk)

                    Text(resetStatusMsg)
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    showForgotPassword = false
                    resetStatusMsg = ""
                } label: {
                    Text(l10n.t("auth.reset.ok"))
                        .font(.bpHeadline())
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .bpAccessibility(label: l10n.t("auth.reset.ok"), hint: l10n.t("auth.reset.ok.hint"), isButton: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 280)
        .background(
            RoundedRectangle(cornerRadius: BPRadius.xxl)
                .fill(Color.bpSurface)
                .overlay(RoundedRectangle(cornerRadius: BPRadius.xxl).strokeBorder(Color.bpInk.opacity(0.07)))
        )
    }

    // MARK: - Skip

    private var skipButton: some View {
        Button { submitSkip() } label: {
            Text(l10n.t("auth.continueAsGuest"))
                .font(.bpScaled(13, weight: .regular))
                .foregroundStyle(Color.bpInk.opacity(0.25))
                .underline(color: Color.bpInk.opacity(0.12))
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
        .bpAccessibility(label: l10n.t("auth.continueAsGuest"), hint: l10n.t("auth.continueAsGuest.hint"), isButton: true)
    }

    // MARK: - Social Proof

    private var socialProof: some View {
        HStack(spacing: 6) {
            HStack(spacing: -6) {
                ForEach(["🟤", "🟡", "⚪️"], id: \.self) { c in
                    Text(c)
                        .font(.bpScaled(10))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.bpInk.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                }
            }
            Text(l10n.t("auth.socialProof"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpInk.opacity(0.2))
        }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("auth.socialProof.a11y"))
    }

    // MARK: - Actions

    private func submit() {
        let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        // --- Local validation ---
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            withAnimation { flowState = .failure(l10n.t("auth.error.fillFields")) }
            BPHaptics.heavy()
            return
        }

        guard isValidEmail(cleanEmail) else {
            withAnimation { flowState = .failure(l10n.t("auth.error.invalidEmail")) }
            BPHaptics.heavy()
            return
        }

        guard password.count >= 6 else {
            withAnimation { flowState = .failure(l10n.t("auth.error.shortPassword")) }
            BPHaptics.heavy()
            return
        }

        flowState = .validating
        let startTime = CFAbsoluteTimeGetCurrent()

        Task {
            // Record pre-API time
            let validationTime = CFAbsoluteTimeGetCurrent() - startTime

            do {
                let targetState: AuthFlowState = tab == .signIn ? .signingIn : .signingUp
                await MainActor.run { flowState = targetState }

                if tab == .signIn {
                    _ = try await AuthService.shared.signIn(
                        email: cleanEmail,
                        password: password
                    )
                } else {
                    _ = try await AuthService.shared.signUp(
                        email: cleanEmail,
                        password: password
                    )
                }

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                let requestTime = totalTime - validationTime

                await MainActor.run {
                    lastMetrics = AuthMetrics(
                        validationTime: validationTime,
                        requestTime: requestTime,
                        totalTime: totalTime
                    )
                    log("[Auth] completed in \(String(format: "%.2f", totalTime))s (validate: \(String(format: "%.2f", validationTime))s, api: \(String(format: "%.2f", requestTime))s)")

                    flowState = .success
                    BPHaptics.success()
                    appState.completeAuth()
                }
            } catch let error as AuthError {
                await MainActor.run {
                    let msg = error.localizedDescription
                    flowState = .failure(msg)
                    BPHaptics.heavy()
                    log("[Auth] error: \(msg)")
                }
                // Auto-clear failure after 4s
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if case .failure = flowState {
                        await MainActor.run {
                            withAnimation(.spring(response: 0.3)) { flowState = .idle }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    flowState = .failure(l10n.t("auth.error.connection"))
                    BPHaptics.heavy()
                    log("[Auth] unexpected error: \(error.localizedDescription)")
                }
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if case .failure = flowState {
                        await MainActor.run {
                            withAnimation(.spring(response: 0.3)) { flowState = .idle }
                        }
                    }
                }
            }
        }
    }

    private func submitSkip() {
        guard !flowState.isLoading else { return }
        log("[Auth] Guest mode")
        appState.completeAuth()
    }

    private func sendPasswordReset() {
        let target = resetEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !target.isEmpty, !isSendingReset else { return }
        guard isValidEmail(target) else {
            resetStatusMsg = l10n.t("auth.error.invalidEmail")
            return
        }

        isSendingReset = true
        Task {
            do {
                try await AuthService.shared.sendPasswordReset(email: target)
                await MainActor.run {
                    resetStatusMsg = String(format: l10n.t("auth.reset.sentMessage"), target)
                    isSendingReset = false
                }
            } catch {
                await MainActor.run {
                    resetStatusMsg = l10n.t("auth.reset.error")
                    isSendingReset = false
                }
            }
        }
    }

    // MARK: - Validation

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Helpers

    private func log(_ msg: String) {
        #if DEBUG
        print("[BarPass] \(msg)")
        #endif
    }
}

// MARK: - Premium Error Toast

private struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var showDismissHint = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpAmber)

            Text(message)
                .font(.bpScaled(14, weight: .medium))
                .foregroundStyle(Color.bpInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.bpScaled(12, weight: .bold))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Color.bpInk.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("auth.dismissError"), hint: l10n.t("auth.dismissError.hint"), isButton: true)
            .opacity(showDismissHint ? 1 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bpAmber.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).delay(0.5)) {
                showDismissHint = true
            }
        }
    }
}

// MARK: - Preview

// NativeAuthView reads AppState, so the canvas traps without it injected.
#Preview("Dark") {
    NativeAuthView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XXXL") {
    NativeAuthView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
