import SwiftUI

// ExploreV2View — Pantalla "Explore" del artifact v17.1 (sección "Tabs",
// líneas 611-740 del HTML). Mapa estilizado de Miami con pines en vivo,
// búsqueda, capas (Trending / Happy Hour / Rooftops / Música en vivo) y la
// tarjeta del venue tocado.
//
// Match de estilo con OnboardingV2Flow.swift y RemyLiveView.swift: fondo
// Miami eye + warm vignette + fade mask + grain, tipografía black rounded
// + serif italic + mono tracked, cards Color.white.opacity(0.04) con stroke
// 0.08, acento Color.bpAmber / bpAmberBright.
//
// Esta vista es standalone: tiene su propio status bar fake porque el
// mockup lo pide, y la data (venues, friends, counts) es literal del
// artifact. El wiring real a VenueStore / mapa nativo / backend es un pase
// siguiente — este pase sólo clona la pantalla.
//
// Limitaciones conocidas:
// - El mapa no es MapKit ni MapLibre: es un canvas estilizado (bloques tipo
//   calles + línea de agua + pines absolutos) que calca el mockup. Un mapa
//   nativo con tiles custom entra después.
// - Los pines, la posición "me", el cluster y el estado "cold" vs "hot" son
//   literales del artifact (left/top en %). No reaccionan a geolocalización.
// - Los pills (Mapa/Lista, Todos/Trending/…) y el callout de CLUB SPACE
//   tienen estado local pero no filtran nada; sólo hacen haptic al tocar.
// - El contador "1.814" junto al buscador es hardcoded; en producción sale
//   del repo de venues.
// - El status bar fake (23:41 · SOS · 63%) se dibuja porque la vista es una
//   captura "en vivo" del mockup; en producción iOS pinta el suyo.

@MainActor
struct ExploreV2View: View {
    @State private var viewMode: ExploreV2ViewMode = .map
    @State private var selectedLayer: ExploreV2Layer = .all
    @State private var selectedPinID: String? = "space"

    var body: some View {
        ZStack {
            ExploreV2Background()

            VStack(spacing: 0) {
                ExploreV2FakeStatusBar()
                    .padding(.top, 14)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                        searchField
                            .padding(.horizontal, 20)

                        layerStrip
                            .padding(.horizontal, 20)

                        friendsStrip
                            .padding(.horizontal, 20)

                        mapCanvas
                            .padding(.horizontal, 20)
                            .padding(.top, 2)

                        tappedCallout
                            .padding(.horizontal, 20)
                            .padding(.top, 2)

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ExploreV2LiveDot()
                Text("EXPLORAR · MIAMI")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Color.bpAmberBright)
            }

            HStack(alignment: .firstTextBaseline) {
                (
                    Text("Explora ")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    + Text("Miami")
                        .font(.system(size: 30, design: .serif).italic())
                        .foregroundStyle(Color.bpAmberBright)
                )
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 10)

                ExploreV2SegmentToggle(selection: $viewMode)
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.6))

            Text("Buscar venues…")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))

            Spacer()

            Text("1.814")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.bpAmber.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Layer pills

    private var layerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExploreV2Layer.allCases) { layer in
                    ExploreV2PinChip(
                        label: layer.label,
                        isOn: selectedLayer == layer
                    ) {
                        tap()
                        selectedLayer = layer
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Friends strip

    private var friendsStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(ExploreV2Friend.sample) { friend in
                    ExploreV2AvatarBadge(friend: friend)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                (
                    Text("Mía, Jules y Dani")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    + Text(" están afuera")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                )
                Text("2 EN WYNWOOD · 1 EN BRICKELL")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            Text("›")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Map

    private var mapCanvas: some View {
        ExploreV2MapCanvas(
            pins: ExploreV2MapPin.sample,
            selectedID: $selectedPinID
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Callout

    private var tappedCallout: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.21, blue: 0.74),
                                Color(red: 0.18, green: 0.06, blue: 0.32)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                Text("S")
                    .font(.system(size: 22, design: .serif).italic())
                    .foregroundStyle(.white)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("CLUB SPACE")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Downtown · Club")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                HStack(spacing: 6) {
                    Text("★ 3.8")
                    Text("·")
                    Text("$$$$")
                    Text("·")
                    Text("Abierto")
                        .foregroundStyle(Color.bpGreen)
                    Text("·")
                    Text("🔥 Trending")
                        .foregroundStyle(Color.bpAmberBright)
                }
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.65))
            }

            Spacer(minLength: 4)

            Button {
                tap()
            } label: {
                Text("Ver venue")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bpAmber))
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Enums / models

private enum ExploreV2ViewMode: String, CaseIterable, Identifiable {
    case map, list
    var id: String { rawValue }
    var label: String { self == .map ? "Mapa" : "Lista" }
}

private enum ExploreV2Layer: String, CaseIterable, Identifiable {
    case all, trending, happyHour, rooftops, liveMusic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "Todos"
        case .trending:  return "🔥 Trending"
        case .happyHour: return "🍹 Happy Hour"
        case .rooftops:  return "🌆 Rooftops"
        case .liveMusic: return "🎸 Música en vivo"
        }
    }
}

private struct ExploreV2Friend: Identifiable {
    let id = UUID()
    let initial: String
    let tint: Color

    static let sample: [ExploreV2Friend] = [
        .init(initial: "M", tint: Color(red: 0.55, green: 0.40, blue: 0.95)),
        .init(initial: "J", tint: Color(red: 0.20, green: 0.90, blue: 0.40)),
        .init(initial: "D", tint: Color(red: 0.92, green: 0.92, blue: 0.95)),
    ]
}

private struct ExploreV2MapPin: Identifiable {
    enum Kind { case cluster, cold, standard, big }
    let id: String
    let name: String
    let x: CGFloat // 0..1
    let y: CGFloat // 0..1
    let kind: Kind

    static let sample: [ExploreV2MapPin] = [
        .init(id: "cluster", name: "12 venues", x: 0.30, y: 0.26, kind: .cluster),
        .init(id: "floyd",   name: "Floyd",     x: 0.64, y: 0.27, kind: .cold),
        .init(id: "e11even", name: "E11EVEN",   x: 0.69, y: 0.37, kind: .standard),
        .init(id: "space",   name: "CLUB SPACE", x: 0.62, y: 0.46, kind: .big),
        .init(id: "blackbird", name: "Blackbird Ordinary", x: 0.40, y: 0.68, kind: .standard),
        .init(id: "sugar",   name: "Sugar Rooftop", x: 0.34, y: 0.78, kind: .standard),
    ]
}

// MARK: - Fake status bar

@MainActor
private struct ExploreV2FakeStatusBar: View {
    var body: some View {
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.bpAmber.opacity(0.3))
                    )
                Text("63%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 22)
    }
}

// MARK: - Live dot

@MainActor
private struct ExploreV2LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.bpAmberBright)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .fill(Color.bpAmberBright)
                    .blur(radius: 4)
                    .opacity(pulse ? 0.3 : 0.75)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Segmented toggle (Mapa / Lista)

@MainActor
private struct ExploreV2SegmentToggle: View {
    @Binding var selection: ExploreV2ViewMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ExploreV2ViewMode.allCases) { mode in
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    selection = mode
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(selection == mode ? .black : Color.white.opacity(0.7))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == mode ? Color.bpAmber : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Pill chip (layer filters)

@MainActor
private struct ExploreV2PinChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(isOn ? .black : Color.white.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn ? Color.bpAmber : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.bpAmberBright : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friends avatar

@MainActor
private struct ExploreV2AvatarBadge: View {
    let friend: ExploreV2Friend

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [friend.tint, friend.tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(friend.initial)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.72))
        }
        .frame(width: 30, height: 30)
        .overlay(
            Circle().strokeBorder(Color(red: 0.03, green: 0.02, blue: 0.06), lineWidth: 2)
        )
    }
}

// MARK: - Map canvas

@MainActor
private struct ExploreV2MapCanvas: View {
    let pins: [ExploreV2MapPin]
    @Binding var selectedID: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base deep navy
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.05, blue: 0.11),
                        Color(red: 0.09, green: 0.03, blue: 0.14)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                // Stylized "water" wash — bottom-left wedge, cooler blue
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.55))
                    p.addQuadCurve(
                        to: CGPoint(x: geo.size.width * 0.42, y: geo.size.height),
                        control: CGPoint(x: geo.size.width * 0.08, y: geo.size.height * 0.95)
                    )
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.14, blue: 0.26).opacity(0.9),
                            Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.95)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // Grid of streets as faint lines
                ExploreV2StreetGrid()
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.6)

                // Diagonal highway accent
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width * 0.1, y: geo.size.height * 0.9))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.9, y: geo.size.height * 0.15))
                }
                .stroke(Color.bpAmber.opacity(0.08), lineWidth: 1.5)

                // Scattered neighborhood labels
                ExploreV2DistrictLabel("WYNWOOD", at: CGPoint(x: geo.size.width * 0.3, y: geo.size.height * 0.18))
                ExploreV2DistrictLabel("DOWNTOWN", at: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.42))
                ExploreV2DistrictLabel("BRICKELL", at: CGPoint(x: geo.size.width * 0.42, y: geo.size.height * 0.62))

                // Overlay chips
                ExploreV2OverlayChip()
                    .position(x: 72, y: 24)

                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                    .position(x: geo.size.width - 28, y: 24)

                // "Me" dot
                ExploreV2MeDot()
                    .position(
                        x: geo.size.width * 0.44,
                        y: geo.size.height * 0.60
                    )

                // Pins
                ForEach(pins) { pin in
                    ExploreV2PinView(pin: pin, isSelected: selectedID == pin.id)
                        .position(
                            x: geo.size.width * pin.x,
                            y: geo.size.height * pin.y
                        )
                        .onTapGesture {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedID = pin.id
                        }
                }
            }
        }
    }
}

// MARK: - Street grid shape

private struct ExploreV2StreetGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let hStep: CGFloat = 36
        let vStep: CGFloat = 40
        var y: CGFloat = 0
        while y < rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += hStep
        }
        var x: CGFloat = 0
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += vStep
        }
        return p
    }
}

// MARK: - District label

@MainActor
private struct ExploreV2DistrictLabel: View {
    let text: String
    let point: CGPoint
    init(_ text: String, at point: CGPoint) {
        self.text = text
        self.point = point
    }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(2.4)
            .foregroundStyle(Color.white.opacity(0.22))
            .position(point)
    }
}

// MARK: - Overlay chip (6 abiertos cerca)

@MainActor
private struct ExploreV2OverlayChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.bpGreen)
                .frame(width: 6, height: 6)
                .overlay(Circle().fill(Color.bpGreen).blur(radius: 3).opacity(0.6))
            Text("6 abiertos cerca")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - "Me" dot

@MainActor
private struct ExploreV2MeDot: View {
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.bpAmber.opacity(0.5), lineWidth: 2)
                .frame(width: 32, height: 32)
                .scaleEffect(ping ? 1.6 : 1.0)
                .opacity(ping ? 0 : 0.9)
            Circle()
                .fill(Color.bpAmber)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ping = true
            }
        }
    }
}

// MARK: - Pin view

@MainActor
private struct ExploreV2PinView: View {
    let pin: ExploreV2MapPin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            dot
            label
        }
    }

    @ViewBuilder
    private var dot: some View {
        switch pin.kind {
        case .cluster:
            ZStack {
                Circle()
                    .fill(Color.bpAmber.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.bpAmberBright, lineWidth: 1.5))
                Text("12")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
        case .cold:
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        case .standard:
            ZStack {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 22, height: 22)
                    .opacity(0.25)
                    .blur(radius: 2)
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 14, height: 14)
            }
        case .big:
            ZStack {
                Circle()
                    .fill(Color.bpAmberBright)
                    .frame(width: 32, height: 32)
                    .opacity(0.35)
                    .blur(radius: 3)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.bpAmberBright, Color.bpAmber],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSelected)
        }
    }

    @ViewBuilder
    private var label: some View {
        let isCold = pin.kind == .cold
        let isBig = pin.kind == .big
        Text(pin.name.uppercased())
            .font(.system(size: isBig ? 10.5 : 9.5, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(
                isCold ? Color.white.opacity(0.5) :
                (isBig ? .white : Color.white.opacity(0.9))
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(Color.black.opacity(isCold ? 0.35 : 0.6))
            )
            .overlay(
                Capsule().strokeBorder(
                    isBig ? Color.bpAmber.opacity(0.6) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
            )
    }
}

// MARK: - Background (Miami eye + warm vignette + grain)

@MainActor
private struct ExploreV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3,
                           height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.08)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.22),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    ExploreV2View()
}
