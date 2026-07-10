import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var engine = PointsEngine.shared
    @State private var animateStats = false
    @State private var showToast = false
    @State private var showGames = false

    private var points: Int { engine.totalXP }
    private var level: String { engine.levelName }
    private var checkins: Int { engine.checkinCount }
    private var nextLevel: String { engine.nextLevelName ?? "Max" }
    private var nextPoints: Int { engine.xpForNextLevel ?? engine.totalXP }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.bpAmber.opacity(0.3), Color.bpAmber.opacity(0.1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().strokeBorder(Color.bpAmber.opacity(0.3), lineWidth: 1.5))

                            Text("🎉")
                                .font(.system(size: 34))
                        }
                        .bpAccessibility(label: "Foto de perfil", hint: "Tu foto de perfil de usuario")

                        VStack(spacing: 4) {
                            Text("Miami Nightlifer")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .bpAccessibility(label: "Miami Nightlifer", hint: "Tu nombre de usuario")

                            HStack(spacing: 6) {
                                Text(level)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.bpAmber)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.25)))
                                    .bpAccessibility(label: level, hint: "Tu nivel actual")
                            }
                        }
                    }
                    .padding(.top, 60)

                    // Points card
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l10n.t("profile.points"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.bpTextSecondary)
                                Text("\(points) BPX")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.bpAmber)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(l10n.t("profile.nextLevel"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.bpTextSecondary)
                                Text(nextLevel)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: animateStats ? geo.size.width * CGFloat(engine.progress) : 0, height: 6)
                                    .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.3), value: animateStats)
                            }
                        }
                        .frame(height: 6)

                        Text(engine.xpForNextLevel != nil ? "\(nextPoints - points) BPX para llegar a \(nextLevel)" : "Nivel máximo alcanzado 🏆")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bpTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.15)))
                    .accessibilityElement(children: .ignore)
                    .bpAccessibility(label: "BarPass Points \(points) BPX", hint: "Tus puntos y progreso al siguiente nivel")
                    .padding(.horizontal, BPSpacing.lg)

                    // Juegos y misiones
                    Button {
                        BPHaptics.light()
                        showGames = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("🎮").font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Juegos y misiones")
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                Text("Trivia diaria y misiones con XP extra")
                                    .font(.system(size: 11)).foregroundStyle(Color.bpTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                        }
                        .padding(16)
                        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.xl))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: "Juegos y misiones", hint: "Abrir trivia diaria y misiones", isButton: true)
                    .padding(.horizontal, BPSpacing.lg)

                    // Stats
                    HStack(spacing: 12) {
                        statCard(value: "\(checkins)", label: l10n.t("profile.checkins"), icon: "mappin.circle.fill")
                        statCard(value: "\(engine.reviewCount)", label: l10n.t("profile.reviews"), icon: "star.fill")
                        statCard(value: "\(engine.shareCount)", label: l10n.t("profile.invited"), icon: "person.2.fill")
                    }
                    .padding(.horizontal, BPSpacing.lg)

                    // How to earn
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.t("profile.howToEarn"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        VStack(spacing: 10) {
                            earnRow(icon: "mappin.circle.fill", action: "Check-in en venue (×\(engine.checkinCount))", points: "+50 BPX")
                            earnRow(icon: "camera.fill", action: "Review con foto (×\(engine.reviewCount))", points: "+75 BPX")
                            earnRow(icon: "sparkles", action: "Crear o completar trip (×\(engine.tripCount))", points: "+100/200 BPX")
                            earnRow(icon: "square.and.arrow.up", action: "Compartir venue (×\(engine.shareCount))", points: "+25 BPX")
                        }
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.white.opacity(0.07)))
                    .accessibilityElement(children: .ignore)
                    .bpAccessibility(label: "Cómo ganar puntos", hint: "Sección de cómo ganar puntos de BarPass")
                    .padding(.horizontal, BPSpacing.lg)

                    // Language selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.t("profile.language"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 10) {
                            ForEach(AppLanguage.allCases) { lang in
                                let on = l10n.language == lang
                                Button {
                                    BPHaptics.light()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        l10n.language = lang
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(lang.flag).font(.system(size: 22))
                                        Text(lang.label)
                                            .font(.system(size: 11, weight: on ? .bold : .regular))
                                            .foregroundStyle(on ? Color.bpAmber : Color.bpTextSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(on ? Color.bpAmber.opacity(0.12) : Color.white.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                        .strokeBorder(on ? Color.bpAmber.opacity(0.4) : Color.white.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: lang.label, hint: "Cambiar idioma de la app", isButton: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.white.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)

                    // Theme selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Tema")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                            ForEach(BPTheme.allCases) { theme in
                                let on = themeService.theme == theme
                                Button {
                                    BPHaptics.medium()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        themeService.theme = theme
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        HStack(spacing: 4) {
                                            Circle().fill(theme.palette.0).frame(width: 14, height: 14)
                                            Circle().fill(theme.palette.1).frame(width: 14, height: 14)
                                        }
                                        Text(theme.label)
                                            .font(.system(size: 11, weight: on ? .bold : .regular))
                                            .foregroundStyle(on ? theme.palette.0 : Color.bpTextSecondary)
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(on ? theme.palette.0.opacity(0.12) : Color.white.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                        .strokeBorder(on ? theme.palette.0.opacity(0.45) : Color.white.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: theme.label, hint: "Cambiar el tema de color de la app", isButton: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.white.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)

                    Spacer(minLength: 120)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.6)) { animateStats = true }
            }
        }
        .overlay(alignment: .top) {
            if showToast, let award = engine.lastAward {
                HStack(spacing: 8) {
                    Text("🏆")
                    Text("+\(award.xp) XP · \(award.action.label)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Color.bpAmber, in: Capsule())
                .shadow(color: Color.bpAmber.opacity(0.4), radius: 12, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showGames) {
            GamificationView()
                .presentationBackground(.black)
        }
        .onChange(of: engine.lastAward?.xp) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) { showToast = false; engine.lastAward = nil }
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.bpAmber)
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.07)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "\(value) \(label)", hint: "Estadística: \(label)")
    }

    private func earnRow(icon: String, action: String, points: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 24)
            Text(action)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer()
            Text(points)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.bpAmber)
        }
    }
}
