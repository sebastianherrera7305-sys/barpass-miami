import SwiftUI

// SocialV2View — Tab Social v17.1 convergida en el artifact fc6e12c7 (owner,
// 2026-10-09). Es la nueva tab Social: historias por venue, feed de "tu gente"
// (eventos organizados, llegadas, salas de historias) y una tarjeta de evento
// que arma un amigo (Vida griega / co-planning).
//
// Vive al lado del SocialView actual sin reemplazarlo; se cablea desde
// MainTabView cuando esté integrado detrás de un kill switch, igual que
// OnboardingV2Flow.
//
// Diseño en línea con OnboardingV2Flow y RemyLiveView: fondo compartido
// (CityArtMiami + vignette + grain), 70pt de spacer bajo la status bar,
// mezcla sans (SF Pro Display 900 rounded) + accent serif italic (bpAmberBright),
// eyebrows monospaced con tracking, tarjetas sobre blanco al 4%.
//
// Limitaciones conocidas (listadas en limitations del StructuredOutput):
// - Avatares son placeholders de color + inicial. El mockup trae SVGs
//   complejos de caras; replicarlos exacto no vale el costo y los avatares
//   reales se enganchan con FriendPresence/UserAvatar en un pase posterior.
// - El contenido (Mía/Jules/Dani/Val, "Sábado de house en Savage Labs")
//   es literal del mockup; cuando esté el feed real se cablean las fuentes.
// - La tab bar inferior está dibujada decorativamente aquí; en producción
//   la pone MainTabView, así que la oculto si la propiedad `embeddedInTabBar`
//   es true (default).

@MainActor
public struct SocialV2View: View {

    /// Cuando esta vista se usa dentro de `MainTabView`, la tab bar nativa
    /// de SwiftUI ya está debajo — no dibujamos la nuestra. En previews
    /// standalone se puede pasar `false` para ver el frame completo.
    private let embeddedInTabBar: Bool

    public init(embeddedInTabBar: Bool = true) {
        self.embeddedInTabBar = embeddedInTabBar
    }

    public var body: some View {
        ZStack {
            SocialV2Background()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 70)

                    // Eyebrow — tiempo real, ciudad, hora
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.bpAmber)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .fill(Color.bpAmber.opacity(0.4))
                                    .frame(width: 12, height: 12)
                                    .blur(radius: 2)
                            )
                        Text("Social · Miami · 23:41")
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(Color.bpAmber)
                    }
                    .padding(.horizontal, 24)

                    // Headline — "Tu gente está afuera" (sans + serif italic)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Tu gente")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1)
                            .foregroundStyle(.white)
                        Text("está afuera")
                            .font(.system(size: 32, design: .serif).italic())
                            .foregroundStyle(Color.bpAmberBright)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    // Sub-digest con contadores
                    (
                        Text("3").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                        + Text(" afuera · ").font(.system(size: 13)).foregroundColor(Color.white.opacity(0.6))
                        + Text("2").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                        + Text(" en camino · Mía acaba de llegar a Blackbird").font(.system(size: 13)).foregroundColor(Color.white.opacity(0.6))
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    // Pills — filtros del feed social
                    pillsRow
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    // "Ahora" — feed de tu gente en este momento
                    nowFeed
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    // Historias de esta noche — rail horizontal de venues
                    storiesSectionHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    storiesRail
                        .padding(.top, 12)

                    // Host card — evento organizado por un amigo
                    hostCard
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    // CTAs — "Levantar la mano" / "Armar algo"
                    bottomCTAs
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    Spacer().frame(height: embeddedInTabBar ? 40 : 100)
                }
            }

            // Tab bar decorativa — solo en previews standalone
            if !embeddedInTabBar {
                VStack {
                    Spacer()
                    SocialV2DecorativeTabBar()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                SocialV2Pill(text: "Ahora", isOn: true)
                SocialV2Pill(text: "Historias · 6")
                SocialV2Pill(text: "Eventos")
                SocialV2Pill(text: "Amigos")
                SocialV2Pill(text: "Chats · 2")
            }
        }
        .scrollClipDisabled()
    }

    private var nowFeed: some View {
        VStack(spacing: 0) {
            SocialV2NowRow(
                avatar: SocialV2Avatar(initial: "M", background: Color(red: 0.55, green: 0.4, blue: 0.95)),
                name: "Mía · Blackbird Ordinary",
                detail: "llegó hace 12 min · Brickell · \u{201C}vengan, está lleno\u{201D}",
                chip: .init(text: "Ir · 9 min", kind: .hot)
            )
            SocialV2Divider()
            SocialV2NowRow(
                avatar: SocialV2Avatar(initial: "J", background: Color(red: 0.2, green: 0.9, blue: 0.4)),
                name: "Jules · con Mía",
                detail: "Blackbird Ordinary · subió 2 historias",
                chip: .init(text: "Ver", kind: .ghost)
            )
            SocialV2Divider()
            SocialV2NowRow(
                avatar: SocialV2Avatar(initial: "D", background: Color(red: 0.92, green: 0.9, blue: 0.95)),
                name: "Dani · en camino a Amor Miami",
                detail: "Uber · llega en 4 min · \u{201C}¿quién viene?\u{201D}",
                chip: .init(text: "Sumarme", kind: .ghost)
            )
            SocialV2Divider()
            SocialV2NowRow(
                avatar: SocialV2Avatar(initial: "V", background: Color(red: 0.1, green: 0.1, blue: 0.13)),
                name: "Val · en casa",
                detail: "\u{201C}salgo a las 00:00, díganme dónde\u{201D}",
                chip: .init(text: "Avisar", kind: .ghost)
            )
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private var storiesSectionHeader: some View {
        HStack {
            Text("Historias de esta noche")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("6 nuevas")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.bpAmber)
        }
    }

    private var storiesRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SocialV2StoryItem(initial: "E", label: "E11EVEN", isNew: true)
                SocialV2StoryItem(initial: "B", label: "Blackbird", isNew: true)
                SocialV2StoryItem(initial: "M", label: "Mango's", isNew: true)
                SocialV2StoryItem(initial: "S", label: "Savage", isNew: false)
                SocialV2StoryItem(initial: "P", label: "El Patio", isNew: false)
                SocialV2StoryItem(initial: "L", label: "LIV", isNew: false)
            }
            .padding(.horizontal, 24)
        }
        .scrollClipDisabled()
    }

    private var hostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Santi organiza · sábado 23:00")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                Text("8 confirmados")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.bpAmber, in: Capsule())
            }

            Text("Sábado de house en Savage Labs")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    SocialV2MiniAvatar(initial: "S", background: Color(red: 1.0, green: 0.42, blue: 0.42))
                    SocialV2MiniAvatar(initial: "M", background: Color(red: 0.55, green: 0.4, blue: 0.95))
                    SocialV2MiniAvatar(initial: "J", background: Color(red: 0.55, green: 0.4, blue: 0.95))
                }
                Text("+ 5 más")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.65))

                Spacer()

                Button {} label: {
                    Text("Voy")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {} label: {
                    Text("Tal vez")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.bpAmber)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.bpAmber.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.4)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.bpAmber.opacity(0.14), Color.bpAmber.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpAmber.opacity(0.4)))
    }

    private var bottomCTAs: some View {
        HStack(spacing: 10) {
            Button {} label: {
                HStack(spacing: 6) {
                    Text("\u{270B}")
                    Text("Levantar la mano")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Button {} label: {
                HStack(spacing: 6) {
                    Text("+")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Text("Armar algo")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Background

@MainActor
private struct SocialV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3, height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * -0.1)
                    .opacity(0.55)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Pills

@MainActor
private struct SocialV2Pill: View {
    let text: String
    var isOn: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                isOn ? AnyShapeStyle(Color.bpAmber) : AnyShapeStyle(Color.white.opacity(0.07)),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(isOn ? Color.bpAmberBright : Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Now feed row

private struct SocialV2ChipSpec {
    enum Kind { case hot, ghost }
    let text: String
    let kind: Kind
}

@MainActor
private struct SocialV2NowRow: View {
    let avatar: SocialV2Avatar
    let name: String
    let detail: String
    let chip: SocialV2ChipSpec

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            chipView
        }
        .padding(.vertical, 8)
    }

    private var chipView: some View {
        Group {
            switch chip.kind {
            case .hot:
                Text(chip.text)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.bpAmber, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
                    .shadow(color: Color.bpAmber.opacity(0.5), radius: 6, y: 0)
            case .ghost:
                Text(chip.text)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.bpAmber.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
            }
        }
    }
}

@MainActor
private struct SocialV2Divider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }
}

// MARK: - Avatars

@MainActor
private struct SocialV2Avatar: View {
    let initial: String
    let background: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [background, background.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(initial)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: 42, height: 42)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

@MainActor
private struct SocialV2MiniAvatar: View {
    let initial: String
    let background: Color

    var body: some View {
        ZStack {
            Circle().fill(background)
            Text(initial)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
    }
}

// MARK: - Stories rail

@MainActor
private struct SocialV2StoryItem: View {
    let initial: String
    let label: String
    let isNew: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.06, blue: 0.13))
                Text(initial)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .overlay(
                Circle().strokeBorder(
                    isNew ? Color.bpAmber : Color.white.opacity(0.2),
                    lineWidth: isNew ? 2 : 1.5
                )
            )
            .shadow(
                color: isNew ? Color.bpAmber.opacity(0.5) : .clear,
                radius: isNew ? 10 : 0
            )

            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Decorative tab bar (previews only)

@MainActor
private struct SocialV2DecorativeTabBar: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SocialV2TabItem.all.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 3) {
                    Image(systemName: t.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(t.label)
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(t.isOn ? Color.bpAmber : Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .background(
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct SocialV2TabItem {
    let label: String
    let icon: String
    let isOn: Bool

    static let all: [SocialV2TabItem] = [
        .init(label: "TONIGHT", icon: "flame.fill", isOn: false),
        .init(label: "EXPLORE", icon: "map", isOn: false),
        .init(label: "SOCIAL", icon: "person.2.fill", isOn: true),
        .init(label: "TRIPS", icon: "suitcase.fill", isOn: false),
        .init(label: "ME", icon: "person.crop.circle", isOn: false),
    ]
}

// MARK: - Preview

#Preview("Social v2 — standalone") {
    SocialV2View(embeddedInTabBar: false)
}

#Preview("Social v2 — embedded") {
    SocialV2View()
}
