import SwiftUI
import AuthenticationServices

// AuthLoginV2View — pantalla "Entrar" del artifact v17.1
// (sección #s-auth, grupo "Cuenta y seguridad"). Reemplaza visualmente a
// NativeAuthView: ojo Miami a full detrás, mascota BarPass, pills de modo
// (Iniciar sesión / Crear cuenta), form glass con email + contraseña +
// link "¿Olvidaste tu contraseña?", CTA "Entrar" (amber con flecha),
// CTA "Continuar con Apple" (fondo oscuro translúcido) y la línea legal
// mono con "Términos" y "Política de privacidad" en amber.
//
// Lo que lee del mockup:
// - Fondo con el eye (CityArtMiami) centrado y a plena opacidad + warm
//   vignette + grain, igual que OB1_Intro en OnboardingV2Flow.swift.
// - Status bar fake (23:41 · SOS · 63%) porque la vista se diseñó como
//   captura; en producción iOS pinta el suyo encima.
// - La mascota del mockup es un PNG inline (base64). Se intenta cargar un
//   asset "BarPassMascot" del bundle, si no existe se dibuja una stand-in
//   amber (silueta "BP") para que la vista nunca aparezca rota.
//
// Entrada pública: AuthLoginV2View con 5 callbacks opcionales (sign-in,
// sign-up, Apple, forgot password, terms/privacy). Si no se le pasan,
// el screen funciona en Previews como pieza visual pura.
//
// Limitaciones conocidas (follow-ups de wiring, no de diseño):
// - No llama a AuthService. Deliberadamente desacoplado para que el PR
//   que registre esta pantalla elija cuándo swappear NativeAuthView.
// - El toggle Iniciar sesión / Crear cuenta cambia el eyebrow del CTA
//   pero no agrega campos extra (nombre, confirmar password): el mockup
//   sólo trae una ruta.
// - "Mostrar" alterna SecureField/TextField localmente; sin autofill ni
//   un/pw iCloud por ahora.
// - "Continuar con Apple" usa SignInWithAppleButton real (black). El
//   onApple callback recibe el ASAuthorizationAppleIDCredential; parseo
//   del token y hop al back lo hace quien monta la vista.
// - La status bar fake vive dentro del safe area del dispositivo (no
//   ignoresSafeArea), para no chocar con la de iOS en pantallas con notch.
// - Las fuentes Instrument Serif / Courier Prime / Bebas del mockup no
//   están en el bundle; aproximamos con .system(design: .serif/.monospaced/.rounded).

@MainActor
struct AuthLoginV2View: View {
    enum Mode: String, CaseIterable {
        case signIn
        case signUp

        var label: String {
            switch self {
            case .signIn: return "Iniciar sesión"
            case .signUp: return "Crear cuenta"
            }
        }

        var cta: String {
            switch self {
            case .signIn: return "Entrar"
            case .signUp: return "Crear cuenta"
            }
        }
    }

    // Callbacks — todos opcionales. Si falta uno, el tap es no-op con
    // haptic (feedback táctil mínimo). Esto permite poner la vista en
    // Previews y en el bootstrap sin forzar wiring todavía.
    var onSignIn: ((_ email: String, _ password: String) -> Void)? = nil
    var onSignUp: ((_ email: String, _ password: String) -> Void)? = nil
    var onAppleCredential: ((ASAuthorizationAppleIDCredential) -> Void)? = nil
    var onForgotPassword: (() -> Void)? = nil
    var onTerms: (() -> Void)? = nil
    var onPrivacy: (() -> Void)? = nil

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @FocusState private var focused: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            AuthLoginV2Background()

            VStack(spacing: 0) {
                // 70pt top spacer below status bar, as per style reference.
                Spacer().frame(height: 70)

                fakeStatusBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        brandLockup
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)

                        modePills
                            .padding(.horizontal, 4)

                        formCard

                        primaryCTA

                        appleCTA

                        legalLine
                            .padding(.top, 2)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
        .onTapGesture { focused = nil }
    }

    // MARK: - Fake status bar (visual nod to the mockup)

    private var fakeStatusBar: some View {
        HStack {
            Text("23:41")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            HStack(spacing: 8) {
                Text("SOS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                Text("63%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Brand lockup (mascot + BAR PASS + tagline)

    private var brandLockup: some View {
        VStack(spacing: 14) {
            AuthLoginV2Mascot()
                .frame(width: 96, height: 96)
                .shadow(color: Color.black.opacity(0.6), radius: 10, y: 8)

            HStack(spacing: 0) {
                Text("BAR")
                    .foregroundStyle(.white)
                Text("PASS")
                    .foregroundStyle(Color.bpAmber)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.bpAmber)
                            .frame(height: 2)
                            .offset(y: 2)
                    }
            }
            .font(.system(size: 26, weight: .black, design: .rounded))
            .tracking(-0.6)

            (
                Text("La noche de Miami, ")
                    .foregroundStyle(Color.white.opacity(0.9))
                + Text("sin fila.")
                    .font(.system(size: 17, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            )
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .shadow(color: Color.black.opacity(0.9), radius: 4)
        }
    }

    // MARK: - Mode pills (Iniciar sesión / Crear cuenta)

    private var modePills: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    tap()
                    withAnimation(.easeOut(duration: 0.2)) {
                        mode = m
                    }
                } label: {
                    Text(m.label)
                        .font(.system(size: 12.5, weight: mode == m ? .black : .semibold, design: .rounded))
                        .foregroundStyle(mode == m ? Color.black : Color.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(mode == m ? Color.bpAmber : Color.white.opacity(0.07))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                mode == m ? Color.bpAmber : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Form card (email + password + forgot link)

    private var formCard: some View {
        VStack(spacing: 10) {
            // Email row
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.4))
                TextField(
                    "",
                    text: $email,
                    prompt: Text("Email").foregroundColor(Color.white.opacity(0.45))
                )
                .focused($focused, equals: .email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .submitLabel(.next)
                .onSubmit { focused = .password }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.4)))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        focused == .email ? Color.bpAmber.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )

            // Password row
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.4))
                Group {
                    if showPassword {
                        TextField(
                            "",
                            text: $password,
                            prompt: Text("Contraseña").foregroundColor(Color.white.opacity(0.45))
                        )
                    } else {
                        SecureField(
                            "",
                            text: $password,
                            prompt: Text("Contraseña").foregroundColor(Color.white.opacity(0.45))
                        )
                    }
                }
                .focused($focused, equals: .password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .submitLabel(.go)
                .onSubmit { submit() }

                Button {
                    tap()
                    showPassword.toggle()
                } label: {
                    Text(showPassword ? "Ocultar" : "Mostrar")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color.bpAmber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Ocultar contraseña" : "Mostrar contraseña")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.4)))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        focused == .password ? Color.bpAmber.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )

            HStack {
                Spacer()
                Button {
                    tap()
                    onForgotPassword?()
                } label: {
                    Text("¿Olvidaste tu contraseña?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 13.0/255, green: 8.0/255, blue: 8.0/255).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Primary CTA (Entrar / Crear cuenta)

    private var primaryCTA: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 9) {
                Text(mode.cta)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(-0.2)
                Text("→")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        colors: [Color.bpAmberBright, Color.bpAmber],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: Color.bpAmber.opacity(0.3), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apple CTA (uses real SignInWithAppleButton for correctness)

    private var appleCTA: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.email, .fullName]
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                    onAppleCredential?(cred)
                }
            case .failure:
                // Silencio deliberado — el flow real logeará desde el
                // sitio que monta la vista. Aquí sólo pintamos el botón.
                break
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Legal line (mono, Términos / Política in amber)

    private var legalLine: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("AL ENTRAR ACEPTAS LOS ")
                .foregroundStyle(Color.white.opacity(0.55))
            Button {
                tap()
                onTerms?()
            } label: {
                Text("TÉRMINOS")
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
            Text(" Y LA ")
                .foregroundStyle(Color.white.opacity(0.55))
            Button {
                tap()
                onPrivacy?()
            } label: {
                Text("POLÍTICA DE PRIVACIDAD")
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
        .tracking(1.4)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func submit() {
        focused = nil
        tap()
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        switch mode {
        case .signIn: onSignIn?(e, p)
        case .signUp: onSignUp?(e, p)
        }
    }

    private func tap() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }
}

// MARK: - Background (Miami eye at full bloom + warm vignette + grain)

@MainActor
private struct AuthLoginV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // Eye at full bloom, centered high — matches .scr default (no
            // .bd-top / .bd-dim variant) of the kit: ojo "a full".
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.0,
                           height: proxy.size.width * 2.0)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * 0.35)
                    .opacity(0.95)
            }
            .ignoresSafeArea()

            // Warm halation vignette — radial, cooler at center.
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade mask — lower half settles into black so the form reads.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.4),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Film grain — reuses the project-wide seeded texture so the
            // transition from onboarding never flickers.
            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Mascot (asset if available, otherwise a safe stand-in)

@MainActor
private struct AuthLoginV2Mascot: View {
    var body: some View {
        ZStack {
            // Try an asset named "BarPassMascot" first; if the catalogue
            // ships it later this just lights up. UIImage(named:) returns
            // nil when missing, so SwiftUI's Image("…") would render a
            // broken placeholder — we gate on the UIImage lookup.
            #if canImport(UIKit)
            if let ui = UIImage(named: "BarPassMascot") {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                standIn
            }
            #else
            standIn
            #endif
        }
    }

    private var standIn: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.bpAmberBright, Color.bpAmber, Color(red: 0.55, green: 0.33, blue: 0.08)],
                    center: .center, startRadius: 2, endRadius: 60
                ))
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2)
                )
            Text("BP")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .shadow(color: Color.white.opacity(0.25), radius: 1, y: -1)
        }
    }
}

#if DEBUG
#Preview("AuthLoginV2 — standalone") {
    AuthLoginV2View()
}

#Preview("AuthLoginV2 — with wiring") {
    AuthLoginV2View(
        onSignIn: { email, _ in print("sign in", email) },
        onSignUp: { email, _ in print("sign up", email) },
        onAppleCredential: { _ in print("apple") },
        onForgotPassword: { print("forgot") },
        onTerms: { print("terms") },
        onPrivacy: { print("privacy") }
    )
}
#endif
