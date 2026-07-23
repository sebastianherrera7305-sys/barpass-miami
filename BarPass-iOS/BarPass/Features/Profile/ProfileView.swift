import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @ObservedObject private var autoplay = AutoplayPreference.shared
    @ObservedObject private var engine = PointsEngine.shared
    @State private var animateStats = false
    @State private var showToast = false
    @State private var showGames = false
    @State private var showTopUp = false
    @State private var showDeleteAccount = false

    private var points: Int { engine.totalXP }
    private var level: String { engine.levelName }
    private var checkins: Int { engine.checkinCount }
    private var nextLevel: String { engine.nextLevelName ?? l10n.t("profile.maxLevel") }
    private var nextPoints: Int { engine.xpForNextLevel ?? engine.totalXP }

    var body: some View {
        ZStack {
            BPBackgroundView()

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
                                .font(.bpScaled(34))
                        }
                        .bpAccessibility(label: l10n.t("profile.avatar"), hint: l10n.t("profile.avatar.hint"))

                        VStack(spacing: 4) {
                            Text(l10n.t("profile.displayName"))
                                .font(.bpScaled(20, weight: .bold))
                                .foregroundStyle(Color.bpInk)
                                .bpAccessibility(label: l10n.t("profile.displayName"), hint: l10n.t("profile.displayName.hint"))

                            HStack(spacing: 6) {
                                Text(level)
                                    .font(.bpScaled(12, weight: .semibold))
                                    .foregroundStyle(Color.bpAmber)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.25)))
                                    .bpAccessibility(label: level, hint: l10n.t("profile.level.hint"))
                            }
                        }
                    }
                    .padding(.top, 60)

                    // Points card
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l10n.t("profile.points"))
                                    .font(.bpScaled(12))
                                    .foregroundStyle(Color.bpTextSecondary)
                                Text(String(format: l10n.t("profile.bpxValue"), points))
                                    .font(.bpScaled(28, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.bpAmber)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(l10n.t("profile.nextLevel"))
                                    .font(.bpScaled(12))
                                    .foregroundStyle(Color.bpTextSecondary)
                                Text(nextLevel)
                                    .font(.bpScaled(16, weight: .bold))
                                    .foregroundStyle(Color.bpInk)
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.bpInk.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: animateStats ? geo.size.width * CGFloat(engine.progress) : 0, height: 6)
                                    .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.3), value: animateStats)
                            }
                        }
                        .frame(height: 6)

                        Text(engine.xpForNextLevel != nil
                             ? String(format: l10n.t("profile.level.progress"), nextPoints - points, nextLevel)
                             : l10n.t("profile.level.max"))
                            .font(.bpScaled(11))
                            .foregroundStyle(Color.bpTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.15)))
                    .accessibilityElement(children: .ignore)
                    .bpAccessibility(label: String(format: l10n.t("profile.points.a11y"), points), hint: l10n.t("profile.points.hint"))
                    .padding(.horizontal, BPSpacing.lg)

                    // BarPass Wallet
                    Button {
                        BPHaptics.light()
                        showTopUp = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("🪙").font(.bpScaled(22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.t("table.wallet.name"))
                                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                                Text(String(format: l10n.t("profile.wallet.balance"), appState.walletBalance))
                                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                        }
                        .padding(16)
                        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("table.wallet.name"), hint: l10n.t("profile.wallet.hint"), isButton: true)
                    .padding(.horizontal, BPSpacing.lg)

                    // Mis pases (historial)
                    NavigationLink {
                        OrderHistoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Text("🎟️").font(.bpScaled(22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.t("profile.passes.title"))
                                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                                Text(l10n.t("profile.passes.subtitle"))
                                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                        }
                        .padding(16)
                        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("profile.passes.title"), hint: l10n.t("profile.passes.hint"), isButton: true)
                    .padding(.horizontal, BPSpacing.lg)

                    // Juegos y misiones
                    Button {
                        BPHaptics.light()
                        showGames = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("🎮").font(.bpScaled(22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.t("profile.games.title"))
                                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                                Text(l10n.t("profile.games.subtitle"))
                                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                        }
                        .padding(16)
                        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("profile.games.title"), hint: l10n.t("profile.games.hint"), isButton: true)
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
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)

                        VStack(spacing: 10) {
                            earnRow(icon: "mappin.circle.fill", action: String(format: l10n.t("profile.earn.checkin"), engine.checkinCount), points: "+50 BPX")
                            earnRow(icon: "camera.fill", action: String(format: l10n.t("profile.earn.review"), engine.reviewCount), points: "+75 BPX")
                            earnRow(icon: "sparkles", action: String(format: l10n.t("profile.earn.trip"), engine.tripCount), points: "+100/200 BPX")
                            earnRow(icon: "square.and.arrow.up", action: String(format: l10n.t("profile.earn.share"), engine.shareCount), points: "+25 BPX")
                        }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
                    .accessibilityElement(children: .ignore)
                    .bpAccessibility(label: l10n.t("profile.howToEarn"), hint: l10n.t("profile.howToEarn.hint"))
                    .padding(.horizontal, BPSpacing.lg)

                    // Language selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.t("profile.language"))
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)

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
                                        Text(lang.flag).font(.bpScaled(22))
                                        Text(lang.label)
                                            .font(.system(size: 11, weight: on ? .bold : .regular))
                                            .foregroundStyle(on ? Color.bpAmber : Color.bpTextSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(on ? Color.bpAmber.opacity(0.12) : Color.bpInk.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                        .strokeBorder(on ? Color.bpAmber.opacity(0.4) : Color.bpInk.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: lang.label, hint: l10n.t("profile.language.hint"), isButton: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)

                    // Theme selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.t("profile.theme"))
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)

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
                                    .background(on ? theme.palette.0.opacity(0.12) : Color.bpInk.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                        .strokeBorder(on ? theme.palette.0.opacity(0.45) : Color.bpInk.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: theme.label, hint: l10n.t("profile.theme.hint"), isButton: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)

                    // Appearance selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.t("profile.appearance"))
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)

                        HStack(spacing: 10) {
                            ForEach(BPAppearance.allCases) { mode in
                                let on = appearanceStore.appearance == mode
                                Button {
                                    BPHaptics.medium()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        appearanceStore.appearance = mode
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mode.emoji).font(.bpScaled(22))
                                        Text(mode.label)
                                            .font(.system(size: 11, weight: on ? .bold : .regular))
                                            .foregroundStyle(on ? Color.bpAmber : Color.bpTextSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(on ? Color.bpAmber.opacity(0.12) : Color.bpInk.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                        .strokeBorder(on ? Color.bpAmber.opacity(0.4) : Color.bpInk.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: mode.label, hint: l10n.t("profile.appearance.hint"), isButton: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)

                    // Autoplay — apagado real, no solo el X de la barra flotante.
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l10n.t("profile.autoplay.title"))
                                .font(.bpScaled(15, weight: .bold))
                                .foregroundStyle(Color.bpInk)
                            Text(l10n.t("profile.autoplay.subtitle"))
                                .font(.bpScaled(11))
                                .foregroundStyle(Color.bpTextSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $autoplay.enabled)
                            .labelsHidden()
                            .tint(Color.bpAmber)
                            .onChange(of: autoplay.enabled) { _, on in
                                BPHaptics.light()
                                if !on { MusicNowPlayingObserver.shared.stop() }
                            }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
                    .padding(.horizontal, BPSpacing.lg)
                    .bpAccessibility(label: l10n.t("profile.autoplay.title"), hint: autoplay.enabled ? l10n.t("profile.autoplay.on") : l10n.t("profile.autoplay.off"), isButton: true)

                    // Account
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t("profile.account"))
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)

                        if let session = AuthService.shared.restoreSession() {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.bpScaled(18)).foregroundStyle(Color.bpGreen)
                                Text(session.user.email ?? l10n.t("profile.account.activeSession"))
                                    .font(.bpScaled(14)).foregroundStyle(Color.bpTextSecondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            Button {
                                BPHaptics.medium()
                                AuthService.shared.signOut()
                                appState.showNativeAuth = true
                            } label: {
                                Text(l10n.t("profile.account.signOut"))
                                    .font(.bpScaled(14, weight: .bold))
                                    .foregroundStyle(Color.bpDanger)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Color.bpDanger.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: l10n.t("profile.account.signOut"), hint: l10n.t("profile.signOut.hint"), isButton: true)

                            Button {
                                BPHaptics.light()
                                showDeleteAccount = true
                            } label: {
                                Text(l10n.t("profile.account.deleteAccount"))
                                    .font(.bpScaled(13, weight: .semibold))
                                    .foregroundStyle(Color.bpTextSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: l10n.t("profile.account.deleteAccount"), hint: l10n.t("deleteAccount.hint"), isButton: true)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.bpScaled(18)).foregroundStyle(Color.bpTextSecondary)
                                Text(l10n.t("profile.account.guest"))
                                    .font(.bpScaled(14)).foregroundStyle(Color.bpTextSecondary)
                                Spacer()
                            }
                            Button {
                                BPHaptics.medium()
                                appState.showNativeAuth = true
                            } label: {
                                Text(l10n.t("profile.account.signIn"))
                                    .font(.bpScaled(14, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Color.bpAmber, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: l10n.t("profile.account.signIn"), hint: "Entrar con tu cuenta para sincronizar", isButton: true)
                        }
                    }
                    .padding(18)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.07)))
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
                        .font(.bpScaled(14, weight: .bold))
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
        .sheet(isPresented: $showTopUp) {
            WalletTopUpView(onSuccess: { _ in })
                .environmentObject(appState)
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView(walletBalance: appState.walletBalance) {
                appState.showNativeAuth = true
            }
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
                .font(.bpScaled(18))
                .foregroundStyle(Color.bpAmber)
            Text(value)
                .font(.bpScaled(20, weight: .black))
                .foregroundStyle(Color.bpInk)
                .contentTransition(.numericText())
            Text(label)
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpInk.opacity(0.07)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "\(value) \(label)", hint: "Estadística: \(label)")
    }

    private func earnRow(icon: String, action: String, points: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 24)
            Text(action)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk.opacity(0.7))
            Spacer()
            Text(points)
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(Color.bpAmber)
        }
    }
}
