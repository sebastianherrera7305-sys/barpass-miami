import SwiftUI

/// Original, hand-drawn mascot badges for cities whose college identity
/// deserves more than an emoji — deliberately NOT a reproduction of any
/// school's actual trademarked logo (no UF "Albert" head, no officially
/// licensed art). Each badge is a from-scratch vector composition in the
/// school's general color story, built with SwiftUI Path/Shape so it scales
/// cleanly at any size with no image assets to ship.
///
/// Cities without a custom badge yet fall back to their CityIdentity emoji —
/// add a case here + a new `case` in the switch as more get designed.
struct CityMascotIcon: View {
    let city: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch city {
            case "Gainesville":
                GatorMascotBadge()
            case "Miami":
                MiamiMascotBadge()
            case "Las Vegas":
                VegasMascotBadge()
            case "New York":
                NewYorkMascotBadge()
            case "Los Angeles":
                LosAngelesMascotBadge()
            case "Tuscaloosa":
                ElephantMascotBadge()
            case "Baton Rouge":
                TigerMascotBadge()
            case "Chapel Hill":
                RamMascotBadge()
            case "Boulder":
                BisonMascotBadge()
            case let c? where CityMascotIcon.letterBadges[c] != nil:
                let spec = CityMascotIcon.letterBadges[c]!
                LetterMarkBadge(text: spec.text, tint: spec.tint, tintBright: spec.tintBright)
            default:
                let identity = CityIdentity.forCity(city)
                Text(identity.emoji)
                    .font(.system(size: size * 0.62))
                    .frame(width: size, height: size)
                    .background(identity.theme.palette.0.opacity(0.15), in: Circle())
            }
        }
        .frame(width: size, height: size)
    }

    /// City → (real school/city abbreviation as plain text, accent,
    /// accent-bright). Plain, unstylized lettering of a school's actual
    /// initials/nickname (UGA, OSU, FSU, ...) — this is nominative
    /// reference to a real name, not a reproduction of any school's
    /// designed wordmark/logo artwork (the trademarked part is the
    /// specific stylized lettering and design, not the bare abbreviation
    /// in a generic system font). Students recognize their school by name
    /// first — this is deliberately closer to "the real thing" than a
    /// generic icon, while staying clear of copying anyone's actual logo.
    fileprivate static let letterBadges: [String: (text: String, tint: Color, tintBright: Color)] = [
        "Austin":          ("ATX",  Color(red: 0.20, green: 0.65, blue: 0.55), Color(red: 0.45, green: 0.90, blue: 0.75)),
        "Nashville":       ("NASH", Color(red: 0.85, green: 0.30, blue: 0.20), Color(red: 1.00, green: 0.55, blue: 0.35)),
        "Chicago":         ("CHI",  Color(red: 0.25, green: 0.55, blue: 0.85), Color(red: 0.55, green: 0.78, blue: 1.00)),
        "New Orleans":     ("NOLA", Color(red: 0.60, green: 0.35, blue: 0.85), Color(red: 0.80, green: 0.60, blue: 1.00)),
        "Tempe":           ("ASU",  Color(red: 0.92, green: 0.35, blue: 0.15), Color(red: 1.00, green: 0.60, blue: 0.30)),
        "Athens":          ("UGA",  Color(red: 0.75, green: 0.15, blue: 0.15), Color(red: 0.95, green: 0.40, blue: 0.35)),
        "Columbus":        ("OSU",  Color(red: 0.75, green: 0.15, blue: 0.15), Color(red: 0.95, green: 0.45, blue: 0.30)),
        "Madison":         ("UW",   Color(red: 0.80, green: 0.10, blue: 0.15), Color(red: 1.00, green: 0.75, blue: 0.15)),
        "Ann Arbor":       ("UM",   Color(red: 0.85, green: 0.75, blue: 0.15), Color(red: 0.05, green: 0.15, blue: 0.30)),
        "Tallahassee":     ("FSU",  Color(red: 0.60, green: 0.10, blue: 0.20), Color(red: 0.90, green: 0.65, blue: 0.15)),
        "Bloomington":     ("IU",   Color(red: 0.70, green: 0.15, blue: 0.20), Color(red: 0.95, green: 0.85, blue: 0.20)),
        "State College":   ("PSU",  Color(red: 0.05, green: 0.15, blue: 0.30), Color(red: 0.85, green: 0.85, blue: 0.85)),
        "College Station": ("TAMU", Color(red: 0.30, green: 0.10, blue: 0.10), Color(red: 0.85, green: 0.70, blue: 0.40)),
        "Oxford":          ("OM",   Color(red: 0.05, green: 0.10, blue: 0.30), Color(red: 0.75, green: 0.15, blue: 0.15)),
    ]
}

/// A bold lettermark badge — the real school/city abbreviation in plain
/// system typography, colored per city. Not a copy of any school's actual
/// designed wordmark (the trademarked stylization), just the real name
/// students already use to refer to their school, set in a neutral font.
struct LetterMarkBadge: View {
    let text: String
    let tint: Color
    let tintBright: Color

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.45), tint.opacity(0.18)], center: .center, startRadius: 0, endRadius: s * 0.55))
                Circle()
                    .strokeBorder(LinearGradient(colors: [tintBright, tint], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.055)
                Text(text)
                    .font(.system(size: text.count > 3 ? s * 0.24 : s * 0.34, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(LinearGradient(colors: [tintBright, tint], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.78)
            }
        }
    }
}

/// An original alligator-jaw badge — wide top-down snout with a jagged
/// tooth line, in Florida's orange/green/blue story. The composition
/// (top-down jaw in a circular patch) is intentionally different from the
/// official side-profile "Albert" head mark: same color language, distinct
/// silhouette and framing, drawn from scratch.
struct GatorMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.05, green: 0.20, blue: 0.16), Color(red: 0.02, green: 0.10, blue: 0.09)],
                            center: .center, startRadius: 0, endRadius: s * 0.55
                        )
                    )
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.15), Color(red: 0.95, green: 0.35, blue: 0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: s * 0.055
                    )

                // Snout — a flattened lens shape spanning most of the badge width.
                SnoutShape()
                    .fill(Color(red: 0.22, green: 0.55, blue: 0.30))
                    .frame(width: s * 0.74, height: s * 0.46)
                    .overlay(
                        SnoutShape()
                            .stroke(Color(red: 0.10, green: 0.32, blue: 0.18), lineWidth: s * 0.02)
                    )

                // Jagged tooth line through the snout's center.
                ZigZagTeeth(points: 7)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: s * 0.62, height: s * 0.14)

                // Nostrils.
                HStack(spacing: s * 0.10) {
                    Circle().fill(Color(red: 0.05, green: 0.14, blue: 0.09)).frame(width: s * 0.06, height: s * 0.06)
                    Circle().fill(Color(red: 0.05, green: 0.14, blue: 0.09)).frame(width: s * 0.06, height: s * 0.06)
                }
                .offset(y: -s * 0.22)

                // Eye ridges.
                HStack(spacing: s * 0.30) {
                    Capsule().fill(Color(red: 1.0, green: 0.55, blue: 0.15)).frame(width: s * 0.16, height: s * 0.045)
                    Capsule().fill(Color(red: 1.0, green: 0.55, blue: 0.15)).frame(width: s * 0.16, height: s * 0.045)
                }
                .offset(y: -s * 0.32)
            }
        }
    }
}

/// A sun-and-palm badge for Miami — original silhouette, amber/pink glow,
/// generic city iconography (no team or brand marks involved here at all).
struct MiamiMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.30, green: 0.10, blue: 0.20), Color(red: 0.10, green: 0.04, blue: 0.10)],
                        center: .center, startRadius: 0, endRadius: s * 0.55
                    ))
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 0.98, green: 0.75, blue: 0.35), Color(red: 0.95, green: 0.45, blue: 0.55)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: s * 0.055
                    )

                // Sun.
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.40), Color(red: 0.95, green: 0.50, blue: 0.35)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.34, height: s * 0.34)
                    .offset(x: s * 0.08, y: -s * 0.16)

                // Palm fronds — three simple curved leaves fanning from a trunk.
                ForEach([-40.0, 0.0, 40.0], id: \.self) { angle in
                    Capsule()
                        .fill(Color(red: 0.15, green: 0.55, blue: 0.40))
                        .frame(width: s * 0.42, height: s * 0.09)
                        .offset(x: s * 0.21)
                        .rotationEffect(.degrees(angle), anchor: .leading)
                }
                .offset(x: -s * 0.10, y: s * 0.10)

                // Trunk.
                Capsule()
                    .fill(Color(red: 0.35, green: 0.24, blue: 0.16))
                    .frame(width: s * 0.07, height: s * 0.30)
                    .offset(x: -s * 0.10, y: s * 0.28)
            }
        }
    }
}

/// A dice badge for Las Vegas — two overlapping dice, neon pink/purple glow.
struct VegasMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.28, green: 0.05, blue: 0.22), Color(red: 0.10, green: 0.02, blue: 0.10)],
                        center: .center, startRadius: 0, endRadius: s * 0.55
                    ))
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.35, blue: 0.80), Color(red: 0.85, green: 0.20, blue: 0.65)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: s * 0.055
                    )

                die(s).offset(x: -s * 0.14, y: s * 0.10).rotationEffect(.degrees(-12))
                die(s).offset(x: s * 0.14, y: -s * 0.10).rotationEffect(.degrees(10))
            }
        }
    }

    private func die(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.05)
            .fill(Color.white.opacity(0.95))
            .frame(width: s * 0.34, height: s * 0.34)
            .overlay(
                VStack(spacing: s * 0.05) {
                    HStack { pip(s); Spacer() }
                    HStack { Spacer(); pip(s); Spacer() }
                    HStack { Spacer(); pip(s) }
                }
                .padding(s * 0.06)
            )
    }

    private func pip(_ s: CGFloat) -> some View {
        Circle().fill(Color(red: 0.85, green: 0.20, blue: 0.65)).frame(width: s * 0.055, height: s * 0.055)
    }
}

/// A skyline badge for New York — simple silhouette + moon, deep blue glow.
struct NewYorkMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.06, green: 0.14, blue: 0.30), Color(red: 0.02, green: 0.05, blue: 0.14)],
                        center: .center, startRadius: 0, endRadius: s * 0.55
                    ))
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 0.45, green: 0.75, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: s * 0.055
                    )

                Circle()
                    .fill(Color(red: 0.85, green: 0.92, blue: 1.0))
                    .frame(width: s * 0.16, height: s * 0.16)
                    .offset(x: s * 0.14, y: -s * 0.22)

                SkylineShape()
                    .fill(Color(red: 0.10, green: 0.20, blue: 0.38))
                    .frame(width: s * 0.7, height: s * 0.34)
                    .offset(y: s * 0.20)
            }
        }
    }
}

/// A palm-and-hills badge for Los Angeles — sunset gradient, palm silhouettes
/// against rolling hills, purple/pink glow.
struct LosAngelesMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.30, green: 0.16, blue: 0.36), Color(red: 0.10, green: 0.05, blue: 0.16)],
                        center: .center, startRadius: 0, endRadius: s * 0.55
                    ))
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 0.78, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.30, blue: 0.85)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: s * 0.055
                    )

                // Sunset disc, low on the horizon.
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.65, blue: 0.55), Color(red: 0.90, green: 0.35, blue: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.4, height: s * 0.4)
                    .offset(y: -s * 0.04)

                // Rolling hills silhouette across the bottom.
                HillsShape()
                    .fill(Color(red: 0.14, green: 0.07, blue: 0.20))
                    .frame(width: s * 0.86, height: s * 0.24)
                    .offset(y: s * 0.26)

                // Two thin palm trunks with a small frond fan, either side.
                ForEach([-1.0, 1.0], id: \.self) { side in
                    ZStack {
                        Capsule()
                            .fill(Color(red: 0.10, green: 0.05, blue: 0.14))
                            .frame(width: s * 0.03, height: s * 0.30)
                        ForEach([-30.0, 0.0, 30.0], id: \.self) { angle in
                            Capsule()
                                .fill(Color(red: 0.10, green: 0.05, blue: 0.14))
                                .frame(width: s * 0.20, height: s * 0.04)
                                .offset(x: side * s * 0.10)
                                .rotationEffect(.degrees(angle), anchor: .leading)
                        }
                        .offset(y: -s * 0.14)
                    }
                    .offset(x: side * s * 0.26, y: s * 0.02)
                }
            }
        }
    }
}

private struct HillsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY * 1.1), control: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct SkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let heights: [CGFloat] = [0.5, 0.75, 0.45, 1.0, 0.6, 0.8, 0.4]
        let step = w / CGFloat(heights.count)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (i, h) in heights.enumerated() {
            let x0 = rect.minX + CGFloat(i) * step
            let y0 = rect.maxY - rect.height * h
            p.addLine(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x0 + step, y: y0))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// An original elephant badge for Tuscaloosa — big ears, curved trunk,
/// crimson/white — distinct from any school's actual mascot artwork.
struct ElephantMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.35, green: 0.05, blue: 0.08), Color(red: 0.12, green: 0.02, blue: 0.03)], center: .center, startRadius: 0, endRadius: s * 0.55))
                Circle().strokeBorder(LinearGradient(colors: [.white, Color(red: 0.85, green: 0.15, blue: 0.15)], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.055)

                // Ears — two large flattened ovals either side.
                HStack(spacing: s * 0.20) {
                    Ellipse().fill(Color(red: 0.55, green: 0.55, blue: 0.58)).frame(width: s * 0.30, height: s * 0.38)
                    Ellipse().fill(Color(red: 0.55, green: 0.55, blue: 0.58)).frame(width: s * 0.30, height: s * 0.38)
                }
                .offset(y: -s * 0.02)

                // Head.
                Circle().fill(Color(red: 0.68, green: 0.68, blue: 0.72)).frame(width: s * 0.36, height: s * 0.36).offset(y: -s * 0.06)

                // Trunk — a curved capsule sweeping down and to one side.
                TrunkShape()
                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.72), style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
                    .frame(width: s * 0.22, height: s * 0.34)
                    .offset(x: s * 0.02, y: s * 0.18)
            }
        }
    }
}

private struct TrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.7), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// An original tiger badge for Baton Rouge — round ears, stripes, purple/gold.
struct TigerMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.25, green: 0.08, blue: 0.35), Color(red: 0.08, green: 0.02, blue: 0.14)], center: .center, startRadius: 0, endRadius: s * 0.55))
                Circle().strokeBorder(LinearGradient(colors: [Color(red: 0.95, green: 0.80, blue: 0.20), Color(red: 0.75, green: 0.55, blue: 0.05)], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.055)

                // Ears.
                HStack(spacing: s * 0.24) {
                    Circle().fill(Color(red: 0.90, green: 0.55, blue: 0.15)).frame(width: s * 0.16, height: s * 0.16)
                    Circle().fill(Color(red: 0.90, green: 0.55, blue: 0.15)).frame(width: s * 0.16, height: s * 0.16)
                }
                .offset(y: -s * 0.20)

                // Face.
                Circle().fill(Color(red: 0.90, green: 0.55, blue: 0.15)).frame(width: s * 0.42, height: s * 0.38).offset(y: s * 0.02)

                // Stripes.
                ForEach([-0.10, 0.0, 0.10], id: \.self) { dx in
                    Capsule()
                        .fill(Color(red: 0.15, green: 0.08, blue: 0.06))
                        .frame(width: s * 0.04, height: s * 0.16)
                        .rotationEffect(.degrees(dx * 200))
                        .offset(x: s * dx * 1.6, y: s * 0.02)
                }

                // Muzzle.
                Ellipse().fill(Color.white.opacity(0.9)).frame(width: s * 0.18, height: s * 0.12).offset(y: s * 0.14)
            }
        }
    }
}

/// An original ram badge for Chapel Hill — curled horns, powder blue.
struct RamMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.32), Color(red: 0.02, green: 0.07, blue: 0.14)], center: .center, startRadius: 0, endRadius: s * 0.55))
                Circle().strokeBorder(LinearGradient(colors: [Color(red: 0.55, green: 0.80, blue: 1.0), Color(red: 0.30, green: 0.55, blue: 0.90)], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.055)

                // Curled horns.
                ForEach([-1.0, 1.0], id: \.self) { side in
                    HornShape()
                        .stroke(Color(red: 0.85, green: 0.90, blue: 0.95), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
                        .frame(width: s * 0.20, height: s * 0.30)
                        .scaleEffect(x: side, y: 1)
                        .offset(x: side * s * 0.22, y: -s * 0.02)
                }

                // Head.
                RoundedRectangle(cornerRadius: s * 0.10)
                    .fill(Color(red: 0.55, green: 0.80, blue: 1.0))
                    .frame(width: s * 0.26, height: s * 0.32)
            }
        }
    }
}

private struct HornShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY * 0.55),
                   control1: CGPoint(x: rect.maxX, y: rect.minY),
                   control2: CGPoint(x: rect.maxX, y: rect.maxY * 0.4))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                   control1: CGPoint(x: rect.minX, y: rect.maxY * 0.75),
                   control2: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// An original bison badge for Boulder — wide horned head, gold/black.
struct BisonMascotBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.20, green: 0.14, blue: 0.02), Color(red: 0.06, green: 0.04, blue: 0.01)], center: .center, startRadius: 0, endRadius: s * 0.55))
                Circle().strokeBorder(LinearGradient(colors: [Color(red: 1.0, green: 0.80, blue: 0.20), Color(red: 0.75, green: 0.55, blue: 0.05)], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.055)

                // Horns.
                HStack(spacing: s * 0.30) {
                    Capsule().fill(Color(red: 0.85, green: 0.85, blue: 0.80)).frame(width: s * 0.06, height: s * 0.18).rotationEffect(.degrees(-30))
                    Capsule().fill(Color(red: 0.85, green: 0.85, blue: 0.80)).frame(width: s * 0.06, height: s * 0.18).rotationEffect(.degrees(30))
                }
                .offset(y: -s * 0.14)

                // Wide shaggy head.
                RoundedRectangle(cornerRadius: s * 0.16)
                    .fill(Color(red: 0.45, green: 0.30, blue: 0.10))
                    .frame(width: s * 0.44, height: s * 0.34)
                    .offset(y: s * 0.02)

                // Snout.
                RoundedRectangle(cornerRadius: s * 0.06)
                    .fill(Color(red: 0.20, green: 0.13, blue: 0.05))
                    .frame(width: s * 0.20, height: s * 0.12)
                    .offset(y: s * 0.16)
            }
        }
    }
}

private struct SnoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + w * 0.18, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX - w * 0.10, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX - w * 0.10, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX + w * 0.18, y: rect.maxY))
        p.closeSubpath()
        _ = h
        return p
    }
}

private struct ZigZagTeeth: Shape {
    var points: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = rect.width / CGFloat(points)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for i in 0...points {
            let x = rect.minX + CGFloat(i) * step
            let y = i.isMultiple(of: 2) ? rect.minY : rect.maxY
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview("Gator Badge") {
    HStack(spacing: 20) {
        CityMascotIcon(city: "Gainesville", size: 56)
        CityMascotIcon(city: "Las Vegas", size: 56)
    }
    .padding(40)
    .background(Color.black)
}
