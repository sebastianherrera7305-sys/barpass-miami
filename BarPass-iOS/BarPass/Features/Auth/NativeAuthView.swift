import SwiftUI

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

    var buttonLabel: String {
        switch self {
        case .idle, .validating, .failure: return ""
        case .signingIn:  return "Iniciando sesión..."
        case .signingUp:  return "Creando cuenta..."
        case .loadingUser: return "Preparando tu experiencia..."
        case .success:    return "¡Bienvenido!"
        }
    }
}

// MARK: - View

struct NativeAuthView: View {
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

    private let amber  = Color.bpAmber
    private let amberB = Color.bpAmberBright

    enum AuthTab { case signIn, signUp }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LinearGradient(
                colors: [Color.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            mainContent

            // Session checking overlay
            if flowState == .idle && contentOpacity < 0.5 {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(amber)
                    Text("Verificando sesión...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
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
                .padding(.bottom, 36)

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

            divider
                .padding(.horizontal, 24)
                .padding(.top, 28)

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

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 80, height: 80)

                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )

                Text("BP")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [amber, amberB],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 5) {
                Text("BarPass")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(-0.4)

                Text("Tu acceso a la mejor noche")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabBtn("Entrar",      for: .signIn)
            tabBtn("Registrarse", for: .signUp)
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
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(tab == t && !flowState.isLoading ? amber : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
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
            field("Email", text: $email,
                  keyboard: .emailAddress, icon: "envelope", secure: false)
            field("Contraseña", text: $password,
                  keyboard: .default, icon: "lock", secure: true)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType, icon: String, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.28))
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
            .foregroundStyle(.white)
            .tint(amber)

            if secure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
            if flowState.isLoading { return flowState.buttonLabel }
            if case .failure = flowState { return "Intentar de nuevo" }
            return tab == .signIn ? "Entrar" : "Crear cuenta"
        }()

        let showSpinner: Bool = {
            switch flowState {
            case .validating, .signingIn, .signingUp, .loadingUser: return true
            default: return false
            }
        }()

        return Button {
            guard !flowState.isLoading else { return }
            submit()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: isDisabled
                                ? [Color.white.opacity(0.08), Color.white.opacity(0.08)]
                                : [amber, amberB],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 52)

                HStack(spacing: 8) {
                    if showSpinner {
                        ProgressView()
                            .tint(isDisabled ? Color.white.opacity(0.3) : .black)
                            .scaleEffect(0.85)
                    }
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isDisabled ? Color.white.opacity(0.25) : .black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.18), value: isDisabled)
        .animation(.easeInOut(duration: 0.18), value: label)
        .shadow(color: isDisabled || flowState.isLoading ? .clear : amber.opacity(0.25),
                radius: 12, y: 4)
        .opacity(flowState.isLoading ? 0.9 : 1)
    }

    // MARK: - Divider

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
            Text("o")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.2))
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    // MARK: - Forgot Password

    private var forgotPasswordLink: some View {
        Button {
            resetEmail = email
            showForgotPassword = true
        } label: {
            Text("¿Olvidaste tu contraseña?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
        .frame(maxWidth: .infinity)
        .bpAccessibility(label: "Olvidé mi contraseña", hint: "Recibirás un enlace para restablecerla", isButton: true)
    }

    // MARK: - Forgot Password Sheet

    private var forgotPasswordSheet: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Spacer()

            if resetStatusMsg.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.bpAmber)

                    Text("Recuperar contraseña")
                        .font(.bpTitle2())
                        .foregroundStyle(.white)

                    Text("Te enviaremos un enlace a tu email para restablecerla.")
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)

                    TextField("Tu email", text: $resetEmail)
                        .font(.bpBody())
                        .foregroundStyle(.white)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.white.opacity(0.07)))
                }
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancelar") {
                        showForgotPassword = false
                        resetStatusMsg = ""
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))

                    Button {
                        sendPasswordReset()
                    } label: {
                        Text("Enviar")
                            .font(.bpHeadline())
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .opacity(resetEmail.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .disabled(resetEmail.trimmingCharacters(in: .whitespaces).isEmpty || isSendingReset)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.bpGreen)

                    Text("Revisa tu email")
                        .font(.bpTitle2())
                        .foregroundStyle(.white)

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
                    Text("OK")
                        .font(.bpHeadline())
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 280)
        .background(
            RoundedRectangle(cornerRadius: BPRadius.xxl)
                .fill(Color(white: 0.06))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.xxl).strokeBorder(Color.white.opacity(0.07)))
        )
    }

    // MARK: - Skip

    private var skipButton: some View {
        Button { submitSkip() } label: {
            Text("Continuar como invitado")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.25))
                .underline(color: Color.white.opacity(0.12))
        }
        .buttonStyle(.plain)
        .disabled(flowState.isLoading)
    }

    // MARK: - Social Proof

    private var socialProof: some View {
        HStack(spacing: 6) {
            HStack(spacing: -6) {
                ForEach(["🟤", "🟡", "⚪️"], id: \.self) { c in
                    Text(c)
                        .font(.system(size: 10))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                }
            }
            Text("+5,000 personas ya salen con BarPass")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.2))
        }
    }

    // MARK: - Actions

    private func submit() {
        let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        // --- Local validation ---
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            withAnimation { flowState = .failure("Please fill in all fields.") }
            BPHaptics.heavy()
            return
        }

        guard isValidEmail(cleanEmail) else {
            withAnimation { flowState = .failure("Please enter a valid email address.") }
            BPHaptics.heavy()
            return
        }

        guard password.count >= 6 else {
            withAnimation { flowState = .failure("Password must be at least 6 characters.") }
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
                    flowState = .failure("We're having trouble connecting right now. Please try again in a moment.")
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
            resetStatusMsg = "Please enter a valid email address."
            return
        }

        isSendingReset = true
        Task {
            do {
                try await AuthService.shared.sendPasswordReset(email: target)
                await MainActor.run {
                    resetStatusMsg = "If \(target) has an account, a reset link has been sent."
                    isSendingReset = false
                }
            } catch {
                await MainActor.run {
                    resetStatusMsg = "We're having trouble sending the reset email. Please try again."
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

    @State private var showDismissHint = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.bpAmber)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
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

// MARK: - Haptic Convenience

private extension BPHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Preview

#Preview {
    NativeAuthView()
}
