import SwiftUI

struct NativeAuthView: View {
    let bridge: NativeBridge

    @EnvironmentObject private var appState: AppState
    @State private var tab:         AuthTab = .signIn
    @State private var email        = ""
    @State private var password     = ""
    @State private var name         = ""
    @State private var isLoading    = false
    @State private var errorMsg     = ""
    @State private var showPassword = false
    @State private var logoScale:   CGFloat = 0.7
    @State private var logoOpacity: Double  = 0

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)
    private let bg    = Color(red: 0.02, green: 0.01, blue: 0.04)

    enum AuthTab { case signIn, signUp }

    var body: some View {
        ZStack {
            // Background
            bg.ignoresSafeArea()

            // Purple glow
            RadialGradient(
                colors: [Color(red: 0.25, green: 0.05, blue: 0.45).opacity(0.6), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Logo section
                    logoSection
                        .padding(.top, 72)
                        .padding(.bottom, 40)

                    // Auth card
                    VStack(spacing: 0) {
                        tabPicker
                            .padding(.bottom, 24)

                        if tab == .signIn { signInFields } else { signUpFields }

                        if !errorMsg.isEmpty { errorBanner }

                        ctaButton
                            .padding(.top, 20)

                        skipButton
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                logoScale   = 1.0
                logoOpacity = 1.0
            }
        }
        .onChange(of: appState.authError) { err in
            guard !err.isEmpty else { return }
            errorMsg = err
            isLoading = false
            appState.authError = ""
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 14) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(gold.opacity(0.08))
                    .frame(width: 104, height: 104)
                Circle()
                    .fill(gold.opacity(0.14))
                    .frame(width: 84, height: 84)
                // Monogram
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.08, blue: 0.20),
                                         Color(red: 0.06, green: 0.04, blue: 0.10)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(gold.opacity(0.35), lineWidth: 1.5)
                        )
                    Text("BP")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [gold, goldB], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            VStack(spacing: 5) {
                Text("BarPass")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(logoOpacity)

                Text("Tu pase a la mejor noche")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .opacity(logoOpacity)
            }
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton("Entrar",      tab: .signIn)
            tabButton("Registrarse", tab: .signUp)
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func tabButton(_ label: String, tab: AuthTab) -> some View {
        let selected = self.tab == tab
        return Button { withAnimation(.spring(response: 0.3)) { self.tab = tab; errorMsg = "" } } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? gold.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? gold.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fields

    private var signInFields: some View {
        VStack(spacing: 12) {
            authField("Email", text: $email, keyboard: .emailAddress, icon: "envelope")
            passwordField
        }
    }

    private var signUpFields: some View {
        VStack(spacing: 12) {
            authField("Nombre", text: $name, keyboard: .default, icon: "person")
            authField("Email",  text: $email, keyboard: .emailAddress, icon: "envelope")
            passwordField
        }
    }

    private func authField(_ placeholder: String, text: Binding<String>,
                           keyboard: UIKeyboardType, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 20)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .tint(gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.09)))
    }

    private var passwordField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 20)
            Group {
                if showPassword {
                    TextField("Contraseña", text: $password)
                } else {
                    SecureField("Contraseña", text: $password)
                }
            }
            .foregroundStyle(.white)
            .tint(gold)
            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.09)))
    }

    // MARK: - Error

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
            Text(errorMsg)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(red: 1, green: 0.35, blue: 0.35).opacity(0.25)))
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button { submit() } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(tab == .signIn ? "Entrar" : "Crear cuenta")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(colors: [gold, goldB], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: gold.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || email.isEmpty || password.isEmpty)
        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.2), value: email.isEmpty || password.isEmpty)
    }

    private var skipButton: some View {
        Button { submitSkip() } label: {
            Text("Continuar sin cuenta →")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.28))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func submit() {
        guard !isLoading else { return }
        errorMsg  = ""
        isLoading = true
        let mode = tab == .signIn ? "login" : "signup"
        bridge.submitNativeAuth(email: email.trimmingCharacters(in: .whitespaces),
                                password: password,
                                name: name.trimmingCharacters(in: .whitespaces),
                                mode: mode)
    }

    private func submitSkip() {
        guard !isLoading else { return }
        isLoading = true
        bridge.submitNativeAuth(email: "", password: "", name: "", mode: "skip")
    }
}

#Preview {
    NativeAuthView(bridge: NativeBridge())
        .environmentObject(AppState())
}
