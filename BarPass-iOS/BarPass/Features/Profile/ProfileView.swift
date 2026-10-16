import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var venueStore: VenueStore
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @ObservedObject private var autoplay = AutoplayPreference.shared
    @ObservedObject private var engine = PointsEngine.shared
    @State private var animateStats = false
    @State private var showToast = false
    @State private var showGames = false
    @State private var showPasses = false
    @State private var showTopUp = false
    @State private var showDeleteAccount = false
    @State private var currentCity: String? = SelectedCityStore.selectedCity
    @State private var affiliatedUniversity: University?
    @State private var affiliatedChapter: GreekChapter?
    @State private var showAffiliationPicker = false
    @State private var showHomeAddress = false
    /// Owner complaint Build 114 (2026-10-14): "nada aparece en otros
    /// lugares que no son Miami". The CityPickerView only runs ONCE at
    /// first launch — after that the user is locked into whichever city
    /// they picked. Reset+re-open the picker from Profile.
    @State private var showCityChange = false
    /// Build 1 of the Profile Reorg (2026-10-14): a top-right gear toggles
    /// a SettingsSheet with the consolidated settings menu. Ships
    /// additively — the inline rows below the fold stay as a safety net
    /// until the owner confirms the sheet behaves. Removing the inline
    /// duplicates lands in a follow-up build.
    @State private var showSettings = false
    /// This screen used to show the l10n placeholder string "Tu Nombre" /
    /// "Your Name" unconditionally — never the real value, never editable.
    /// Every profile looked identical and unnamed; a chapter member roster
    /// had nothing real to display per member either. nil while loading, so
    /// the placeholder text still shows briefly rather than "" flashing.
    @State private var displayName: String?
    @State private var avatarConfig: AvatarConfig?
    @State private var showEditDisplayName = false
    @State private var showAvatarEditor = false
    // Debug previews — Tonight v17.1 companion screens 8-11, still unwired
    // to the main flow. Lets the owner see them in TestFlight 88+ without
    // replacing the existing TripDetail / PlanView / VenueDetail yet.
    @State private var showRemyLivePreview = false
    @State private var showGroupNightPreview = false
    @State private var showVenuePulsePreview = false
    @State private var showNightRecapPreview = false
    // Gallery v17.1 previews — 12 pantallas más (artifact fc6e12c7).
    @State private var showExploreV2 = false
    @State private var showSocialV2 = false
    @State private var showTripsListV2 = false
    @State private var showPriorityEntryV2 = false
    @State private var showSkipTheLineV2 = false
    @State private var showActivePassV2 = false
    @State private var showCartV2 = false
    @State private var showOpenTabV2 = false
    @State private var showAuthLoginV2 = false
    @State private var showGamesMissionsV2 = false
    @State private var showFindMyPeopleV2 = false
    @State private var showYourSignalV2 = false
    @State private var displayNameDraft = ""
    @State private var isSavingDisplayName = false
    @State private var displayNameSaveError: String?

    // Build 1.1 — Posts tipo IG
    @State private var myPosts: [UserPost] = []
    @State private var myPostsCount: Int = 0
    @State private var showPostComposer = false
    @State private var selectedPost: UserPost?

    // Night Recap — entrada real (no DEBUG). Se consulta el mismo agregador
    // que arma la pantalla (`NightRecapStore.load()`) sobre la ventana
    // "anoche" (ayer 18:00 → hoy 06:00); si no hubo check-ins reales, la fila
    // no se dibuja. La ausencia no se rinde como "0 paradas": sin noche, no
    // hay fila. El debug tray sigue teniendo su propia entrada con `.mockup`.
    @State private var nightRecapData: NightRecapData?
    @State private var showNightRecap = false

    private var affiliationSubtitle: String {
        guard let uni = affiliatedUniversity else { return l10n.t("greek.profile.noneHint") }
        if let chapter = affiliatedChapter { return "\(uni.shortName ?? uni.name) · \(chapter.fraternityName)" }
        return uni.shortName ?? uni.name
    }

    private var points: Int { engine.totalXP }
    private var level: String { engine.levelName }
    private var checkins: Int { engine.checkinCount }
    private var nextLevel: String { engine.nextLevelName ?? l10n.t("profile.maxLevel") }
    private var nextPoints: Int { engine.xpForNextLevel ?? engine.totalXP }

    var body: some View {
        // ProfileView had no NavigationStack of its own, and MainTabView gives
        // the tabs none, so its one NavigationLink — "Mis pases" — pushed
        // nothing: the row highlighted and the screen stayed put. The stack
        // lives here now, with the bar hidden because this screen draws its
        // own header; pushed destinations keep their own.
        NavigationStack {
        ZStack {
            BPBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 14) {
                        Button {
                            BPHaptics.light()
                            showAvatarEditor = true
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(
                                    name: displayName ?? "?", avatarUrl: nil,
                                    avatarConfig: avatarConfig, size: 80, animated: true
                                )
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.bpAmber, Color.bpSurface)
                                    .offset(x: 2, y: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: l10n.t("profile.avatar"), hint: l10n.t("profile.avatar.hint"), isButton: true)

                        VStack(spacing: 4) {
                            Button {
                                BPHaptics.light()
                                displayNameDraft = displayName ?? ""
                                showEditDisplayName = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(displayName?.isEmpty == false ? displayName! : l10n.t("profile.displayName"))
                                        .font(.bpScaled(20, weight: .bold))
                                        .foregroundStyle(Color.bpInk)
                                    Image(systemName: "pencil")
                                        .font(.bpScaled(12))
                                        .foregroundStyle(Color.bpTextTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: displayName ?? l10n.t("profile.displayName"), hint: l10n.t("profile.displayName.hint"), isButton: true)

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

                    // Build 1.1 — contador de posts junto al nivel + botón +
                    HStack(spacing: 24) {
                        statInline(value: "\(myPostsCount)", label: "posts")
                        statInline(value: "\(engine.checkinCount)", label: "check-ins")
                        statInline(value: "\(engine.reviewCount)", label: "reviews")
                        Spacer()
                        Button {
                            BPHaptics.medium()
                            showPostComposer = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background(Color.bpAmber, in: Circle())
                                .shadow(color: Color.bpAmber.opacity(0.4), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: "Crear post", hint: "Publica una foto en tu perfil", isButton: true)
                    }
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.top, 4)

                    // Build 1.1 — grid de posts tipo IG. Vacío-state visible
                    // (el owner pidió "no posts falsos ni próximamente") —
                    // dice "Aún no hay posts" + hint para tocar +.
                    PostGridSection(
                        userId: AuthService.shared.restoreSession()?.user.id ?? "",
                        posts: myPosts,
                        isOwner: true,
                        onTapPost: { post in selectedPost = post }
                    )
                    .padding(.horizontal, 2)

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
                    .helpTarget("profile.pointsCard")

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
                    .helpTarget("profile.wallet")

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
                    .helpTarget("profile.passes")

                    // Legal y ayuda — contacto, reglas de contenido, términos,
                    // privacidad y cuentas bloqueadas.
                    //
                    // Va ARRIBA y no al pie junto a "Cerrar sesión", que es
                    // donde la costumbre la pondría: es la sección que el
                    // revisor de Apple entra a buscar (directriz 1.2 pide el
                    // contacto publicado y alcanzable desde la app), este
                    // Perfil scrollea mucho, y algo que hay que buscar 30
                    // segundos se reporta como "we were unable to locate".
                    // La fila entera vive en LegalAndHelpView.swift.
                    // Build 1.1: removidos del scroll los duplicados que
                    // ahora viven en el ⚙ sheet exclusivamente — Legal,
                    // Dirección de casa, Ciudad switcher. El owner pidió
                    // "sin duplicados". Los handlers siguen cableados en
                    // SettingsSheet → showHomeAddress / showCityChange y
                    // esas sheets se montan abajo igual.

                    // "Tu última noche" — Night Recap entry point
                    //
                    // Sólo aparece si el agregador real (`NightRecapStore.load()`)
                    // encontró al menos un check-in dentro de la ventana "anoche"
                    // (ayer 18:00 → hoy 06:00 en hora local). Noches sólo con
                    // órdenes, sin salidas registradas, o estados `.empty` /
                    // `.failed` / `.loading` → la fila no se dibuja. El debug tray
                    // de más abajo sigue teniendo su propia entrada con `.mockup`.
                    if let recap = nightRecapData, recap.stops > 0 {
                        nightRecapRow(data: recap)
                    }

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
                    .helpTarget("profile.games")

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

                    // Appearance selector removed 2026-08-28 — TestFlight feedback:
                    // a tester picked "Claro" and the whole app broke ("pierde
                    // todos los Features del Background"). Light mode was never
                    // actually designed: BPBackgroundView's non-dark branch is a
                    // flat Color.bpBackground fill with none of the psychedelic
                    // city art, and every screen this session touched assumes
                    // the dark palette. Rather than finish designing a real light
                    // mode, the honest fix is to stop offering a mode that isn't
                    // built — AppearanceStore now always resolves to dark (see
                    // ThemeService.swift), so this control has nothing to do.

                    // Build 1.1 — removidos del scroll: Autoplay toggle,
                    // City switcher, Universidad / Greek, sección Account
                    // completa (email + Cerrar sesión + Eliminar cuenta).
                    // Todos siguen accesibles desde el ⚙ gear → SettingsSheet.
                    // Mantenemos el VStack Account como contenedor vacío para
                    // no romper los debug buttons que viven adentro.

                    VStack(alignment: .leading, spacing: 12) {
                        if AuthService.shared.restoreSession() != nil {

                            // Debug previews — Tonight v17.1 screens 8-11, not yet
                            // wired to the main nav. Lets the owner see them in
                            // TestFlight without replacing TripDetail / PlanView
                            // / VenueDetail yet.
                            VStack(spacing: 8) {
                                Text("VISTAS PREVIAS v17.1")
                                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                    .tracking(2)
                                    .foregroundStyle(Color.bpAmber)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 14)
                                debugButton("Remy en vivo") { showRemyLivePreview = true }
                                // These three only have mockup initializers
                                // (sample Trip / mockup venue / .mockup recap),
                                // all fenced under #if DEBUG in their files —
                                // so the buttons exist only in Debug builds.
                                #if DEBUG
                                debugButton("La noche del grupo") { showGroupNightPreview = true }
                                debugButton("Venue con pulso") { showVenuePulsePreview = true }
                                debugButton("Recap y racha") { showNightRecapPreview = true }
                                #endif
                                debugButton("Explore") { showExploreV2 = true }
                                debugButton("Social") { showSocialV2 = true }
                                debugButton("Trips (lista)") { showTripsListV2 = true }
                                // The V2 Priority hub takes callbacks that
                                // only the real presenter (RootView) wires;
                                // calling it bare from the debug tray would
                                // render fabricated "CLUB SPACE" defaults
                                // and three dead cards. DEBUG-only.
                                #if DEBUG
                                debugButton("Priority Entry") { showPriorityEntryV2 = true }
                                #endif
                                debugButton("Skip the Line") { showSkipTheLineV2 = true }
                                #if DEBUG
                                debugButton("Pase activo") { showActivePassV2 = true }
                                #endif
                                debugButton("Carrito") { showCartV2 = true }
                                debugButton("Cuenta abierta") { showOpenTabV2 = true }
                                debugButton("Entrar (auth)") { showAuthLoginV2 = true }
                                debugButton("Juegos y misiones") { showGamesMissionsV2 = true }
                                debugButton("Encontrar a mi gente") { showFindMyPeopleV2 = true }
                                debugButton("Tu señal") { showYourSignalV2 = true }
                            }
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
        // Build 126 — gear as FLOATING overlay button, NOT ToolbarItem.
        //
        // Build 123/124 had: `.toolbar(.visible, for: .navigationBar)` +
        // `.navigationBarTitleDisplayMode(.inline)` +
        // `.toolbarBackground(.hidden, for: .navigationBar)` + a
        // `ToolbarItem(.topBarTrailing)` with the gear. That combination
        // crashed deterministically on device the moment the user tapped
        // the "Yo" tab (Build 124 TestFlight reports). The current working
        // hypothesis — unverified without a stack trace — is a conflict
        // between the ancestor NavigationStack in RootView (which lives
        // under `.ignoresSafeArea(.container, edges: .all)`) and this
        // view's INNER NavigationStack trying to materialize a visible
        // nav bar through those stripped safe-area insets.
        //
        // A floating overlay button sidesteps every one of those modifiers:
        // no `.toolbar(.visible)`, no `.toolbarBackground`, no
        // `.navigationBarTitleDisplayMode`, no `ToolbarItem`. The gear
        // lives in the same ZStack as the BPBackgroundView + ScrollView,
        // anchored topTrailing with the top safe area reserved manually.
        // Loses zero functionality — the gear still opens SettingsSheet —
        // but the nav bar stays hidden (how every other tab renders).
        .overlay(alignment: .topTrailing) {
            Button {
                BPHaptics.light()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(width: 36, height: 36)
                    .background(Color.bpCardBackground.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 56)
            .padding(.trailing, 18)
            .bpAccessibility(label: l10n.t("profile.settings.title"), isButton: true)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsSheet(
                    currentCity: currentCity,
                    autoplayEnabled: $autoplay.enabled,
                    onDirecciónCasa: { showSettings = false; showHomeAddress = true },
                    onCiudad: { showSettings = false; showCityChange = true },
                    onUniversidad: { showSettings = false; showAffiliationPicker = true },
                    onEliminarCuenta: { showSettings = false; showDeleteAccount = true },
                    onCerrarSesion: {
                        BPHaptics.medium()
                        AuthService.shared.signOut()
                        appState.resetUserState()
                        appState.showNativeAuth = true
                        showSettings = false
                    }
                )
            }
            .presentationBackground(.black)
            .preferredColorScheme(.dark)
        }
        // Sheets re-cableados acá después de haber quitado las filas
        // inline (Build 1.1) — los triggers ahora viven en SettingsSheet.
        .sheet(isPresented: $showHomeAddress) {
            HomeAddressSettingsView()
        }
        .sheet(isPresented: $showCityChange) {
            NavigationStack {
                CityPickerView {
                    currentCity = SelectedCityStore.selectedCity
                    showCityChange = false
                }
            }
            .presentationBackground(.black)
        }
        .navigationDestination(isPresented: $showPasses) { OrderHistoryView() }
        // The "Mis pases" Home Screen quick action lands on this tab and asks
        // for the history, so the shortcut ends where its label promises.
        .onChange(of: appState.openPassesRequested) { _, requested in
            guard requested else { return }
            showPasses = true
            appState.openPassesRequested = false
        }
        .sheet(isPresented: $showGames) {
            Group {
                if V2Flags.gamesV2 {
                    GamesMissionsV2View()
                } else {
                    GamificationView()
                }
            }
            .environmentObject(appState)
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
        // Debug previews — see @State block above
        .sheet(isPresented: $showRemyLivePreview) {
            RemyLiveView()
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showGroupNightPreview) {
            // GroupNightView ahora exige un `Trip` real. Para el debug
            // preview usamos el sample `Trip.groupNightSample` (sólo DEBUG)
            // dentro de un `TripStore` aislado para que `currentTrip` lo
            // encuentre y la UI pueda ejercer los mutate paths (joinStop,
            // ensureInviteCode) sin tocar la red.
            #if DEBUG
            GroupNightView(trip: Trip.groupNightSample)
                .environmentObject(appState)
                .environmentObject({
                    let store = TripStore(repository: RepositoryDependencies.trip)
                    store.trips = [Trip.groupNightSample]
                    return store
                }())
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showVenuePulsePreview) {
            // Mockup init is #if DEBUG in VenuePulseView; Release gets nothing.
            #if DEBUG
            VenuePulseView(
                venueName: "Club Space",
                subtitleAccent: "ahora mismo",
                openUntil: "cierra a las 06:00",
                fillPercent: 78
            ).environmentObject(appState)
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showNightRecapPreview) {
            // Debug tray preview: inyecta el mockup para visualizar el diseño
            // sin depender de check-ins reales del día anterior. `.mockup`
            // vive bajo `#if DEBUG`, así que la rama Release cae en EmptyView.
            #if DEBUG
            NightRecapView(data: .mockup)
                .environmentObject(appState)
                .environmentObject(venueStore)
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showExploreV2) {
            ExploreV2View()
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showSocialV2) {
            SocialV2View(embeddedInTabBar: false)
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showTripsListV2) {
            TripsListV2View()
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showPriorityEntryV2) {
            // Bare V2 view (DEBUG-only button above): defaults render "CLUB
            // SPACE" + no-op cards, so the sheet body is itself DEBUG-only.
            #if DEBUG
            PriorityEntryV2View().environmentObject(appState)
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showSkipTheLineV2) { SkipTheLineV2View().environmentObject(appState) }
        .sheet(isPresented: $showActivePassV2) {
            // Sample-pass init is #if DEBUG in ActivePassV2View.
            #if DEBUG
            ActivePassV2View().environmentObject(appState)
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showCartV2) { CartV2View().environmentObject(appState) }
        .sheet(isPresented: $showOpenTabV2) {
            OpenTabV2View()
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showAuthLoginV2) { AuthLoginV2Container().environmentObject(appState) }
        .sheet(isPresented: $showGamesMissionsV2) { GamesMissionsV2View().environmentObject(appState) }
        .sheet(isPresented: $showFindMyPeopleV2) { FindMyPeopleV2View().environmentObject(appState) }
        .sheet(isPresented: $showYourSignalV2) { YourSignalV2View().environmentObject(appState) }
        .sheet(isPresented: $showAffiliationPicker) {
            AffiliationPickerView { uni, chapter in
                affiliatedUniversity = uni
                affiliatedChapter = chapter
            }
        }
        .task { await loadAffiliation() }
        .task { displayName = (try? await RepositoryDependencies.displayName.getDisplayName()) ?? nil }
        .task { avatarConfig = (try? await RepositoryDependencies.avatar.getAvatarConfig()) ?? nil }
        .task { await probeNightRecap() }
        .task { await loadMyPosts() }
        .sheet(isPresented: $showPostComposer) {
            PostComposerView { post in
                myPosts.insert(post, at: 0)
                myPostsCount += 1
            }
            .environmentObject(venueStore)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post, isOwner: true) { deleted in
                myPosts.removeAll { $0.id == deleted.id }
                myPostsCount = max(0, myPostsCount - 1)
            }
        }
        .sheet(isPresented: $showNightRecap) {
            // Real-data entrada: `NightRecapView(data: ...)` rinde el payload
            // ya cargado. El CTA del propio recap llama a `onDismiss`, que
            // cierra la sheet; el swipe-down del sistema también la cierra.
            NightRecapView(data: nightRecapData, onDismiss: { showNightRecap = false })
                .environmentObject(appState)
                .environmentObject(venueStore)
        }
        .sheet(isPresented: $showEditDisplayName) {
            editDisplayNameSheet
        }
        .sheet(isPresented: $showAvatarEditor) {
            AvatarEditorView(current: avatarConfig, repository: RepositoryDependencies.avatar) { saved in
                avatarConfig = saved
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
    }

    /// Fila "Tu última noche" — eyebrow amber "ANOCHE", headline con cantidad
    /// de paradas y rango horario real ("3 venues · 22:14 → 02:05"), chevron.
    /// Mismo lenguaje visual que el resto de filas del Profile (bpSurface +
    /// borde amber tenue + corner xl).
    private func nightRecapRow(data: NightRecapData) -> some View {
        Button {
            BPHaptics.light()
            showNightRecap = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundStyle(Color.bpAmber)
                        Text("ANOCHE")
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(2.4)
                            .foregroundStyle(Color.bpAmber)
                    }
                    Text(nightRecapHeadline(for: data))
                        .font(.bpScaled(15, weight: .bold))
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(16)
            .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(
            label: "Tu última noche",
            hint: nightRecapHeadline(for: data),
            isButton: true
        )
        .padding(.horizontal, BPSpacing.lg)
        .helpTarget("profile.nightRecap")
    }

    /// Construye "N venues · HH:mm → HH:mm" a partir del payload real. Con
    /// una sola parada se cae a "1 venue · HH:mm" (no inventar llegada ni
    /// cierre). Un moment sin tiempo no debería existir (vienen de check-ins
    /// con `checked_in_at`), pero si pasara se omite el rango.
    private func nightRecapHeadline(for data: NightRecapData) -> String {
        let noun = data.stops == 1 ? "venue" : "venues"
        let first = data.moments.first?.time
        let last  = data.moments.last?.time
        switch (first, last) {
        case let (f?, l?) where data.stops > 1 && f != l:
            return "\(data.stops) \(noun) · \(f) → \(l)"
        case let (f?, _):
            return "\(data.stops) \(noun) · \(f)"
        default:
            return "\(data.stops) \(noun)"
        }
    }

    /// Consulta el mismo agregador que arma el recap. El resultado se guarda
    /// localmente para rendir la fila sólo cuando hay noche real que mostrar
    /// (≥ 1 check-in). Fallos de red o estado vacío → `nil` → fila oculta.
    /// Sin side effects fuera de `nightRecapData`.
    /// Carga los posts propios para el grid del perfil + conteo.
    /// RLS filtra server-side (ver user_posts_schema.sql): propio
    /// siempre visible, el resto por amistad/privacidad.
    private func loadMyPosts() async {
        guard let userId = AuthService.shared.restoreSession()?.user.id else { return }
        let repo: UserPostRepository = RepositoryDependencies.userPost
        if let fetched = try? await repo.posts(forUser: userId, limit: 60) {
            myPosts = fetched
            myPostsCount = fetched.count
        }
    }

    private func probeNightRecap() async {
        let store = NightRecapStore(venueStore: venueStore)
        await store.load()
        if case .loaded(let data) = store.state, data.stops > 0 {
            nightRecapData = data
        } else {
            nightRecapData = nil
        }
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            BPHaptics.light()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.bpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpAmber.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    /// Stat compacto para la fila header tipo IG (sin tarjeta, mono).
    private func statInline(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.bpInk)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.bpTextSecondary)
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
        .bpAccessibility(label: "\(value) \(label)", hint: String(format: l10n.t("profile.stat.hint"), label))
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

    private func loadAffiliation() async {
        guard let affiliation = try? await RepositoryDependencies.profileAffiliation.getAffiliation() else { return }
        if let uid = affiliation.universityId {
            affiliatedUniversity = try? await RepositoryDependencies.greekLife.university(id: uid)
        }
        if let cid = affiliation.chapterId {
            affiliatedChapter = try? await RepositoryDependencies.greekLife.chapter(id: cid)
        }
    }

    private var editDisplayNameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(l10n.t("profile.displayName.hint"), text: $displayNameDraft)
                        .textInputAutocapitalization(.words)
                        .onChange(of: displayNameDraft) { _, _ in
                            if displayNameSaveError != nil { displayNameSaveError = nil }
                        }
                }
                if let displayNameSaveError {
                    Section {
                        Text(displayNameSaveError)
                            .font(.bpCaption())
                            .foregroundStyle(Color.bpDanger)
                    }
                }
            }
            .navigationTitle(l10n.t("profile.displayName"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("greek.chat.cancel")) {
                        displayNameSaveError = nil
                        showEditDisplayName = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSavingDisplayName {
                        ProgressView()
                    } else {
                        Button(l10n.t("greek.events.form.save")) { saveDisplayName() }
                            .disabled(displayNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([displayNameSaveError == nil ? .height(160) : .height(230)])
    }

    private func saveDisplayName() {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSavingDisplayName = true
        displayNameSaveError = nil
        // "No deja guardar y si me salgo no se ve" (Build 81 comment): the
        // write was `try? await` with the error path only resetting the spinner
        // — a Supabase/network failure looked identical to tapping an inert
        // button, and dismissing the sheet left the old name on screen because
        // we only wrote `displayName = trimmed` on success. Surface the error
        // inline, keep the sheet open so the draft isn't lost, and let the user
        // retry or cancel out knowingly.
        Task {
            do {
                try await RepositoryDependencies.displayName.setDisplayName(trimmed)
                await MainActor.run {
                    displayName = trimmed
                    isSavingDisplayName = false
                    showEditDisplayName = false
                    BPHaptics.success()
                }
            } catch {
                await MainActor.run {
                    isSavingDisplayName = false
                    displayNameSaveError = l10n.t("api.error.operationFailed")
                    BPHaptics.error()
                }
            }
        }
    }
}

// MARK: - Settings sheet (Build 1 of Profile reorg, 2026-10-14)

/// Consolidated settings menu reachable from the gear in Profile's toolbar.
/// Ships ADDITIVELY: the inline rows below the fold in ProfileView stay as
/// a safety net until the owner confirms the sheet behaves correctly on
/// device, then they get removed. Every callback here routes BACK to the
/// existing ProfileView state (`showHomeAddress`, `showCityChange`,
/// `showAffiliationPicker`, `showDeleteAccount`, `AuthService.signOut`) —
/// no new sheets, no duplicate state, no architectural change.
///
/// "Notificaciones" opens the iOS Settings app at the BarPass bundle so the
/// user can toggle push/location/mic/photos exactly where the system owns
/// those switches; there is no in-app notifications settings screen today
/// and faking one would be worse than deep-linking honestly.
///
/// "Ayuda / Soporte" and "Legal" both land on the existing
/// `LegalAndHelpView`, which already carries the real support contact,
/// terms, and privacy policy.
@MainActor
private struct SettingsSheet: View {
    let currentCity: String?
    @Binding var autoplayEnabled: Bool
    let onDirecciónCasa: () -> Void
    let onCiudad: () -> Void
    let onUniversidad: () -> Void
    let onEliminarCuenta: () -> Void
    let onCerrarSesion: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var privacy = ProfilePrivacyStore.shared

    var body: some View {
        List {
            Section("Cuenta y perfil") {
                row("Dirección de casa", icon: "house.fill", onTap: onDirecciónCasa)
                row("Ciudad", icon: "mappin.and.ellipse",
                    subtitle: currentCity ?? "Elige tu ciudad", onTap: onCiudad)
                row("Universidad / fraternidad", icon: "graduationcap.fill", onTap: onUniversidad)
            }
            Section("Apariencia y preferencias") {
                languageRow
                themeRow
                autoplayRow
            }
            Section(header: Text("Privacidad"),
                    footer: Text("Si activás cuenta privada, solo tus amigos aceptados ven tus posts. Si no, cualquier usuario de BarPass puede verlos desde tu perfil.")) {
                privacyRow
            }
            Section("Notificaciones") {
                row("Notificaciones del sistema", icon: "bell.fill", onTap: openSystemSettings)
            }
            Section("Ayuda y legal") {
                NavigationLink {
                    LegalAndHelpView()
                } label: {
                    settingsRowLabel("Ayuda y soporte", icon: "lifepreserver")
                }
                NavigationLink {
                    LegalAndHelpView()
                } label: {
                    settingsRowLabel("Legal y políticas", icon: "doc.text.fill")
                }
            }
            Section("Sesión") {
                Button(role: .destructive) {
                    onCerrarSesion()
                } label: {
                    settingsRowLabel("Cerrar sesión", icon: "arrow.backward.circle.fill")
                        .foregroundStyle(Color.bpDanger)
                }
                Button(role: .destructive) {
                    onEliminarCuenta()
                } label: {
                    settingsRowLabel("Eliminar cuenta", icon: "trash.fill")
                        .foregroundStyle(Color.bpDanger)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Listo") { dismiss() }
                    .foregroundStyle(Color.bpAmber)
            }
        }
    }

    // MARK: - Rows

    private var languageRow: some View {
        HStack {
            settingsRowLabel("Idioma", icon: "character.bubble.fill")
            Spacer()
            Picker("", selection: $l10n.language) {
                Text("Español").tag(AppLanguage.es)
                Text("English").tag(AppLanguage.en)
                Text("Português").tag(AppLanguage.pt)
            }
            .pickerStyle(.menu)
            .tint(Color.bpAmber)
        }
    }

    /// Tema: AppearanceStore now always resolves to dark (ThemeService 2026-08-28
    /// decision — the non-dark branch was never finished). Shown here as
    /// read-only so the owner can see the control exists without re-enabling
    /// a broken toggle.
    private var themeRow: some View {
        HStack {
            settingsRowLabel("Tema", icon: "paintbrush.fill")
            Spacer()
            Text("Oscuro")
                .font(.system(size: 14))
                .foregroundStyle(Color.bpTextSecondary)
        }
    }

    private var autoplayRow: some View {
        HStack {
            settingsRowLabel("Autoplay", icon: "play.circle.fill")
            Spacer()
            Toggle("", isOn: $autoplayEnabled)
                .labelsHidden()
                .tint(Color.bpAmber)
        }
    }

    /// Toggle "Cuenta privada". `nil` → disabled hasta que
    /// ProfilePrivacyStore cargue el valor inicial del server.
    private var privacyRow: some View {
        HStack {
            settingsRowLabel("Cuenta privada", icon: "lock.fill")
            Spacer()
            if let current = privacy.isPrivate {
                Toggle("", isOn: Binding(
                    get: { current },
                    set: { newValue in
                        BPHaptics.light()
                        Task { await privacy.setPrivate(newValue) }
                    }
                ))
                .labelsHidden()
                .tint(Color.bpAmber)
                .disabled(privacy.isSaving)
            } else {
                ProgressView().tint(Color.bpAmber)
                    .task { await privacy.refresh() }
            }
        }
    }

    private func row(_ title: String, icon: String,
                     subtitle: String? = nil,
                     onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.bpInk)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bpTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.bpTextTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 24)
            Text(title).foregroundStyle(Color.bpInk)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
