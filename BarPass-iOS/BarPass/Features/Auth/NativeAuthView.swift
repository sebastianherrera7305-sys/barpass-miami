import SwiftUI

struct NativeAuthView: View {
    let bridge: NativeBridge

    @EnvironmentObject private var appState: AppState
    @State private var tab:          AuthTab = .signIn
    @State private var email         = ""
    @State private var password      = ""
    @State private var name          = ""
    @State private var isLoading     = false
    @State private var errorMsg      = ""
    @State private var showPassword  = false
    @State private var contentOpacity: Double  = 0
    @State private var contentY:       CGFloat = 24

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    enum AuthTab { case signIn, signUp }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Very subtle top glow — color-neutral
            LinearGradient(
                colors: [Color.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    logoSection
                        .padding(.top, 68)
                        .padding(.bottom, 44)

                    tabPicker
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                    fieldsSection
                        .padding(.horizontal, 24)

                    if !errorMsg.isEmpty {
                        errorBanner
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
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
                        .padding(.top, 36)
                        .padding(.bottom, 48)
                }
            }
            .opacity(contentOpacity)
            .offset(y: contentY)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.08)) {
                contentOpacity = 1
                contentY       = 0
            }
        }
        .onChange(of: appState.authError) { err in
            guard !err.isEmpty else { return }
            withAnimation { errorMsg = err }
            isLoading = false
            appState.authError = ""
        }
    }

    // MARK: - Logo

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
                        LinearGradient(colors: [amber, amberB],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
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

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabBtn("Entrar",      for: .signIn)
            tabBtn("Registrarse", for: .signUp)
        }
    }

    private func tabBtn(_ label: String, for t: AuthTab) -> some View {
        let active = tab == t
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                tab = t
                errorMsg = ""
            }
        } label: {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity)

                // Underline indicator
                Capsule()
                    .fill(active ? amber : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: active)
    }

    // MARK: - Fields

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(spacing: 10) {
            if tab == .signUp {
                field("Nombre completo", text: $name,
                      keyboard: .default, icon: "person", secure: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
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

    // MARK: - Error

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
            Text(errorMsg)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.2))
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - CTA

    private var ctaButton: some View {
        let disabled = isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty

        return Button { submit() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: disabled
                                ? [Color.white.opacity(0.08), Color.white.opacity(0.08)]
                                : [amber, amberB],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 52)

                if isLoading {
                    ProgressView()
                        .tint(disabled ? Color.white.opacity(0.3) : .black)
                } else {
                    Text(tab == .signIn ? "Entrar" : "Crear cuenta")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(disabled ? Color.white.opacity(0.25) : .black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.18), value: disabled)
        .shadow(color: disabled ? .clear : amber.opacity(0.25), radius: 12, y: 4)
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

    // MARK: - Skip

    private var skipButton: some View {
        Button { submitSkip() } label: {
            Text("Continuar como invitado")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.25))
                .underline(color: Color.white.opacity(0.12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Social proof

    private var socialProof: some View {
        HStack(spacing: 6) {
            // Stacked avatar dots
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
        guard !isLoading else { return }
        withAnimation { errorMsg = "" }
        isLoading = true
        bridge.submitNativeAuth(
            email:    email.trimmingCharacters(in: .whitespaces),
            password: password,
            name:     name.trimmingCharacters(in: .whitespaces),
            mode:     tab == .signIn ? "login" : "signup"
        )
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
