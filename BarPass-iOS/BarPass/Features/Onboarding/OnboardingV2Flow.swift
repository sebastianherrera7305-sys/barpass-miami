import SwiftUI
import CoreLocation

// OnboardingV2 — 7 pantallas de "primera apertura" convergidas en el artifact
// 294356f9 (owner, 2026-10-09). Reemplaza OnboardingVideoView (placeholder
// permanente — los clips Higgsfield nunca se grabaron) y absorbe el TasteQuiz
// anterior en la pantalla 3 ("Gusto por swipe").
//
// Gated detrás de AppState.useOnboardingV2 por si rollback.
//
// Pantallas: 1 Intro · 2 Valor antes de cuenta · 3 Gusto por swipe ·
// 4 Avatar desde tu cara · 5 Primera noche · 6 Registro post-valor ·
// 7 Avisos con motivo.
//
// Estado: 1-3 implementadas con el layout del mockup. 4-7 son placeholders
// funcionales con el copy correcto y botón "Continuar" para que el flujo
// cierre; se implementan en pases siguientes.
//
// Las fuentes del mockup (Bebas Neue, Instrument Serif, Courier Prime) no
// están en el bundle. Uso aproximaciones del sistema:
//   display 70s → .system(.largeTitle, design: .rounded, weight: .black) + .textCase(uppercase) + tracking
//   editorial accent → .system(design: .serif).italic()
//   ticket mono → .system(design: .monospaced)
// Agregar las .ttf custom es un paso aparte que no bloquea esto.

enum OnboardingV2Step: Int, CaseIterable {
    case intro = 0
    case valueFirst
    case swipeTaste
    case faceAvatar
    case firstNight
    case saveAccount
    case notifications

    var eyebrow: String {
        switch self {
        case .intro, .valueFirst, .swipeTaste, .faceAvatar,
             .firstNight, .saveAccount, .notifications:
            return "1 · Primera apertura"
        }
    }
}

@MainActor
final class OnboardingV2Model: ObservableObject {
    @Published var step: OnboardingV2Step = .intro
    @Published var swipeIndex: Int = 0
    @Published var swipeLiked: [Bool] = []

    /// 5 propuestas reales para el swipe de gusto. Los IDs se mapean a
    /// venues reales de la catálogo Miami cuando el flujo esté integrado
    /// con VenueStore; por ahora son literales del mockup.
    let swipeOptions: [SwipeCardData] = [
        .init(name: "Sugar", neighborhood: "Brickell · abre hasta 02:00",
              tags: ["rooftop", "house"], price: "$$$$", vibe: "Vista a la bahía"),
        .init(name: "Space", neighborhood: "Downtown · abre toda la noche",
              tags: ["techno", "club"], price: "$$$", vibe: "Terraza al amanecer"),
        .init(name: "The Vault", neighborhood: "Miami Beach · abre 23:00",
              tags: ["lounge", "cocktails"], price: "$$$", vibe: "Jazz en vivo"),
        .init(name: "LIV", neighborhood: "Fontainebleau · abre 23:00",
              tags: ["club", "hip hop"], price: "$$$$", vibe: "Celebridades, bottle service"),
        .init(name: "E11EVEN", neighborhood: "Downtown · 24h",
              tags: ["club", "edm"], price: "$$$$", vibe: "Nunca cierra"),
    ]

    func advance() {
        if let next = OnboardingV2Step(rawValue: step.rawValue + 1) {
            withAnimation(.easeOut(duration: 0.35)) { step = next }
        }
    }

    func skipToEnd(_ complete: () -> Void) {
        complete()
    }

    func recordSwipe(liked: Bool, model: SwipeCardData) {
        swipeLiked.append(liked)
        swipeIndex += 1
    }
}

struct SwipeCardData: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let neighborhood: String
    let tags: [String]
    let price: String
    let vibe: String
}

// MARK: - Flow container

@MainActor
struct OnboardingV2Flow: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = OnboardingV2Model()

    var body: some View {
        ZStack {
            OnboardingV2Background(step: model.step)

            Group {
                switch model.step {
                case .intro:        OB1_Intro(model: model, onComplete: complete)
                case .valueFirst:   OB2_ValueFirst(model: model)
                case .swipeTaste:   OB3_SwipeTaste(model: model)
                case .faceAvatar:   OB4_FaceAvatar(model: model)
                case .firstNight:   OB5_FirstNight(model: model)
                case .saveAccount:  OB6_SaveAccount(model: model, onComplete: complete)
                case .notifications: OB7_Notifications(model: model, onComplete: complete)
                }
            }
            .transition(.opacity)

            // Status bar + SOS pin on every screen except intro
            if model.step != .intro {
                VStack {
                    HStack {
                        Spacer()
                        Text("SOS")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.bpAmber)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                    }
                    .padding(.top, 18).padding(.horizontal, 28)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func complete() {
        appState.completeOnboardingV2()
    }
}

// MARK: - Background with Miami eye + warm vignette + grain

@MainActor
private struct OnboardingV2Background: View {
    let step: OnboardingV2Step

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // The real Miami eye asset — same one Tonight v17.1 uses — but
            // positioned per screen. Intro: full bloom center. 2-5: rays only
            // in top third. 6-7: nearly flat so the forms don't fight the
            // forms-first content.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * eyeScale, height: proxy.size.width * eyeScale)
                    .position(x: proxy.size.width * 0.5, y: eyeCenterY(in: proxy.size.height))
                    .opacity(eyeOpacity)
            }
            .ignoresSafeArea()

            // Warm vignette halation — radial, cooler at center, warm at edges
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade mask so the lower half settles into black
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92), Color.black],
                startPoint: UnitPoint(x: 0.5, y: fadeStart),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Film grain overlay — reuses the existing seeded GrainTexture
            // so it never flickers between screens.
            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var eyeScale: CGFloat {
        switch step {
        case .intro:                                 return 2.0
        case .valueFirst, .swipeTaste, .faceAvatar, .firstNight: return 2.3
        case .saveAccount, .notifications:           return 2.4
        }
    }

    private func eyeCenterY(in height: CGFloat) -> CGFloat {
        switch step {
        case .intro: return height * 0.35
        case .valueFirst, .swipeTaste, .faceAvatar, .firstNight: return height * -0.1
        case .saveAccount, .notifications: return height * -0.2
        }
    }

    private var eyeOpacity: Double {
        switch step {
        case .intro: return 0.95
        case .valueFirst, .swipeTaste, .faceAvatar, .firstNight: return 0.6
        case .saveAccount, .notifications: return 0.35
        }
    }

    private var fadeStart: Double {
        switch step {
        case .intro: return 0.6
        case .valueFirst, .swipeTaste, .faceAvatar, .firstNight: return 0.3
        case .saveAccount, .notifications: return 0.15
        }
    }
}

// MARK: - Screen 1 · Intro (3.5s auto-advance + Skip)

@MainActor
private struct OB1_Intro: View {
    @ObservedObject var model: OnboardingV2Model
    let onComplete: () -> Void
    @State private var bloom = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.advance()
                } label: {
                    Text("Saltar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.black.opacity(0.4), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                }
                .padding(.top, 60).padding(.trailing, 20)
            }

            Spacer()

            VStack(spacing: 18) {
                // The wordmark — BAR (ink/white) + PASS (amber), the one
                // the brand actually uses, with the amber underline under PASS.
                HStack(spacing: 0) {
                    Text("BAR")
                        .foregroundStyle(.white)
                    Text("PASS")
                        .foregroundStyle(Color.bpAmber)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.bpAmber)
                                .frame(height: 4)
                                .offset(y: 6)
                        }
                }
                .font(.system(size: 54, weight: .black, design: .rounded))
                .tracking(-1.5)
                .opacity(bloom ? 1 : 0)
                .offset(y: bloom ? 0 : 20)

                Text("M · I · A · M · I")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .opacity(bloom ? 1 : 0)

                Text("La noche, servida")
                    .font(.system(size: 24, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
                    .opacity(bloom ? 1 : 0)
                    .padding(.top, 10)
            }

            Spacer()

            Text("MIAMI · DESDE 2026")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(3.5)
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.bottom, 60)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { bloom = true }
            // 3.5 s auto-advance per spec. User can Skip at any moment.
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if model.step == .intro { model.advance() }
            }
        }
    }
}

// MARK: - Screen 2 · Valor antes de la cuenta

@MainActor
private struct OB2_ValueFirst: View {
    @ObservedObject var model: OnboardingV2Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 70)

            Text("Miami · ahora mismo")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(Color.bpAmber)
                .padding(.horizontal, 24)

            // Headline mezcla sans + serif italic — "Esta noche {está pasando}"
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Esta noche")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                Text("está pasando")
                    .font(.system(size: 38, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            }
            .padding(.horizontal, 24).padding(.top, 8)

            // Pulse strip — 4 real signals right now
            HStack(spacing: 10) {
                PulseCard(big: "182", small: "ABIERTOS", tint: .white)
                PulseCard(big: "91%", small: "LLENO · LIV", tint: Color.bpAmber)
                PulseCard(big: "72%", small: "LLENO · SPACE", tint: Color.bpAmber)
                PulseCard(big: "87%", small: "TRANQUILO", tint: Color.bpAmberBright)
            }
            .padding(.horizontal, 24).padding(.top, 22)

            Spacer()

            // Remy's offer — the one bit of serif italic that reads as voice
            VStack(alignment: .leading, spacing: 10) {
                Text("Remy · tu concierge")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Dame")
                        .font(.system(size: 26, design: .serif).italic())
                        .foregroundStyle(.white)
                    Text("60 segundos")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.bpAmberBright)
                    Text(".")
                        .font(.system(size: 26, design: .serif).italic())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Button {
                model.advance()
            } label: {
                HStack {
                    Text("Armar mi noche")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.black)
                }
                .padding(.vertical, 18).padding(.horizontal, 22)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bpAmberBright, lineWidth: 1))
                .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)

            Text("Cuenta después · cuando tengas algo que guardar")
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 40)
        }
    }
}

@MainActor
private struct PulseCard: View {
    let big: String
    let small: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(small)
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Screen 3 · Gusto por swipe

@MainActor
private struct OB3_SwipeTaste: View {
    @ObservedObject var model: OnboardingV2Model
    @State private var dragX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 70)

            HStack {
                Text("Remy aprende · \(min(model.swipeIndex + 1, model.swipeOptions.count)) / \(model.swipeOptions.count)")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                Button("Saltar") { model.advance() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 24)

            Text("¿Irías este fin?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 10)

            Spacer()

            // Current swipe card
            if model.swipeIndex < model.swipeOptions.count {
                let card = model.swipeOptions[model.swipeIndex]
                SwipeVenueCard(card: card)
                    .rotationEffect(.degrees(Double(dragX) / 25.0))
                    .offset(x: dragX)
                    .overlay(alignment: .topLeading) {
                        if dragX < -30 {
                            Text("NO")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(Color.bpDanger)
                                .padding(14)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bpDanger, lineWidth: 3))
                                .rotationEffect(.degrees(-18))
                                .padding(16)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if dragX > 30 {
                            Text("IRÍA")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(Color.bpAmber)
                                .padding(14)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bpAmber, lineWidth: 3))
                                .rotationEffect(.degrees(14))
                                .padding(16)
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in dragX = v.translation.width }
                            .onEnded { v in
                                let threshold: CGFloat = 100
                                if abs(v.translation.width) > threshold {
                                    let liked = v.translation.width > 0
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        dragX = liked ? 500 : -500
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        dragX = 0
                                        model.recordSwipe(liked: liked, model: card)
                                        if model.swipeIndex >= model.swipeOptions.count {
                                            model.advance()
                                        }
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3)) { dragX = 0 }
                                }
                            }
                    )
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Action row — explicit buttons for people who don't discover drag
            HStack(spacing: 18) {
                CircleAction(symbol: "xmark", color: Color.bpDanger) {
                    if model.swipeIndex < model.swipeOptions.count {
                        let c = model.swipeOptions[model.swipeIndex]
                        model.recordSwipe(liked: false, model: c)
                        if model.swipeIndex >= model.swipeOptions.count { model.advance() }
                    }
                }
                Text("desliza")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.4))
                CircleAction(symbol: "heart.fill", color: Color.bpAmber) {
                    if model.swipeIndex < model.swipeOptions.count {
                        let c = model.swipeOptions[model.swipeIndex]
                        model.recordSwipe(liked: true, model: c)
                        if model.swipeIndex >= model.swipeOptions.count { model.advance() }
                    }
                }
            }
            .padding(.vertical, 20)

            // Footer: lo que Remy ya aprendió
            VStack(alignment: .leading, spacing: 8) {
                Text("Lo que Remy ya sabe de ti")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.5))

                let learned = learnedTags()
                FlowRow(spacing: 6) {
                    ForEach(learned, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.bpAmberBright)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.bpAmber.opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func learnedTags() -> [String] {
        var tags = Set<String>()
        for (i, liked) in model.swipeLiked.enumerated() where liked {
            let card = model.swipeOptions[i]
            card.tags.forEach { tags.insert($0) }
            // Extract one word from neighborhood: "Brickell · abre hasta 02:00" → "Brickell"
            if let first = card.neighborhood.split(separator: " ").first {
                tags.insert(String(first))
            }
        }
        // Add inferred "no X" tags from refusals (very simple heuristic)
        for (i, liked) in model.swipeLiked.enumerated() where !liked {
            for t in model.swipeOptions[i].tags {
                if !tags.contains(t) { tags.insert("no \(t)") }
            }
        }
        return Array(tags.prefix(6))
    }
}

@MainActor
private struct SwipeVenueCard: View {
    let card: SwipeCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area — placeholder gradient. Will carry venue media
            // once wired to VenueStore in a follow-up.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.3, green: 0.1, blue: 0.4),
                             Color(red: 0.1, green: 0.05, blue: 0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color.bpAmberBright)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.black.opacity(0.55), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3)))
                        }
                    }
                    Text(card.name)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text(card.neighborhood)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(16)
            }
            .frame(height: 300)

            // Info strip
            HStack(spacing: 14) {
                Text(card.price)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                Divider().frame(height: 16).background(Color.white.opacity(0.15))
                Text(card.vibe)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
            }
            .padding(14)
            .background(Color.black.opacity(0.5))
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}

@MainActor
private struct CircleAction: View {
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
                .background(Color.black.opacity(0.6), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.5), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal flow layout — wraps children to next line when they overflow.
/// SwiftUI doesn't ship one; this is a tiny custom Layout for the taste chips.
/// Layout protocol is NOT @MainActor-isolated — leaving the struct nonisolated.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Screens 4-7 · Stubs (copy real, visual placeholder)
// Each has the mockup's exact title + description, a reproduction of the
// section rhythm, and a "Continuar" button. They are honest stubs — the
// real screens come in the next passes.

@MainActor
private struct OB4_FaceAvatar: View {
    @ObservedObject var model: OnboardingV2Model
    var body: some View {
        StubScreen(
            number: 4, title: "Tu avatar", italic: "desde tu cara",
            message: "Selfie → análisis en el teléfono (tono, pelo, lentes) → avatar propio. Es tuyo: cuesta dejarlo.",
            cta: "Tomar selfie",
            secondaryCTA: "Más tarde",
            onPrimary: { model.advance() },
            onSecondary: { model.advance() }
        )
    }
}

@MainActor
private struct OB5_FirstNight: View {
    @ObservedObject var model: OnboardingV2Model
    var body: some View {
        StubScreen(
            number: 5, title: "Esta noche", italic: "ya está armada",
            message: "Remy armó una noche de 3 paradas para esta noche. Guardarla la hace tuya.",
            cta: "Ver mi noche",
            secondaryCTA: nil,
            onPrimary: { model.advance() },
            onSecondary: nil
        )
    }
}

@MainActor
private struct OB6_SaveAccount: View {
    @ObservedObject var model: OnboardingV2Model
    let onComplete: () -> Void
    var body: some View {
        StubScreen(
            number: 6, title: "Guarda", italic: "tu noche",
            message: "Lo que ya ganaste se pierde si salís. Es la noche 1 de tu racha.",
            cta: "Crear cuenta",
            secondaryCTA: "Ya tengo",
            onPrimary: { model.advance() },
            onSecondary: { model.advance() }
        )
    }
}

@MainActor
private struct OB7_Notifications: View {
    @ObservedObject var model: OnboardingV2Model
    let onComplete: () -> Void
    var body: some View {
        StubScreen(
            number: 7, title: "Avisos", italic: "con motivo",
            message: "La fila bajó. Tu grupo llegó. Mejor hora para entrar. Nada que no te sirva.",
            cta: "Avisarme",
            secondaryCTA: "Después",
            onPrimary: onComplete,
            onSecondary: onComplete
        )
    }
}

@MainActor
private struct StubScreen: View {
    let number: Int
    let title: String
    let italic: String
    let message: String
    let cta: String
    let secondaryCTA: String?
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 70)

            Text("1 · Primera apertura · \(number) de 7")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color.bpAmber)
                .padding(.horizontal, 24)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                Text(italic)
                    .font(.system(size: 40, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            }
            .padding(.horizontal, 24).padding(.top, 8)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24).padding(.top, 18)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(cta)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)

                if let secondaryCTA, let onSecondary {
                    Button(action: onSecondary) {
                        Text(secondaryCTA)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }
}
