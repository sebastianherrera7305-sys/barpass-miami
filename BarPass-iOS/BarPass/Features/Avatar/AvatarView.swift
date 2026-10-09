import SwiftUI

/// The shared, animated avatar renderer. Every place a user's identity
/// shows up in the Social Graph (Friends list, search results, "out
/// tonight", the editor preview, the user's own Profile) draws through
/// this one view instead of re-implementing circles/initials locally.
///
/// Precedence, decided once here: a real uploaded photo (`avatarUrl`)
/// always wins over a drawn `avatarConfig` — a photo is a stronger
/// identity signal than an illustration. If neither is set, initials.
struct AvatarView: View {
    let name: String
    let avatarUrl: String?
    let avatarConfig: AvatarConfig?
    var size: CGFloat = 44
    /// Idle motion is a real cost on long lists (Friends can be 100+
    /// rows) — only the editor preview and small "hero" placements
    /// (Profile header, the entry point itself) opt in.
    var animated: Bool = false

    var body: some View {
        Group {
            if let avatarUrl, let parsed = URL(string: avatarUrl) {
                CachedImage(url: parsed, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.bpSurface, in: Circle())
        .overlay(Circle().strokeBorder(Color.bpAmber.opacity(0.35)))
        .clipShape(Circle())
    }

    @ViewBuilder private var fallback: some View {
        if let avatarConfig {
            AvatarIllustration(config: avatarConfig, size: size, animated: animated)
        } else {
            initialsLabel
        }
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.bpAmber)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// The illustration itself — plain SwiftUI shapes layered by z-index, no
/// external art assets. "2D pero dinámico": a slow idle bob plus a real
/// blink loop, not a static drawing, when `animated` is true.
struct AvatarIllustration: View {
    let config: AvatarConfig
    var size: CGFloat = 44
    var animated: Bool = false

    @State private var bob = false
    @State private var blinking = false

    var body: some View {
        ZStack {
            outfit
            head
            hair
            accessory
        }
        .frame(width: size, height: size)
        .offset(y: animated && bob ? -size * 0.015 : 0)
        .animation(animated ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil, value: bob)
        .onAppear {
            guard animated else { return }
            bob = true
            scheduleBlink()
        }
    }

    private var outfit: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(config.outfitColor.color)
            .frame(width: size * 0.92, height: size * 0.42)
            .offset(y: size * 0.34)
    }

    private var head: some View {
        ZStack {
            Circle()
                .fill(config.skinTone.color)
                .frame(width: size * 0.64, height: size * 0.64)
            face
        }
        .offset(y: -size * 0.06)
    }

    private var face: some View {
        VStack(spacing: size * 0.05) {
            HStack(spacing: size * 0.14) {
                eye
                eye
            }
            mouth
        }
        .offset(y: size * 0.03)
    }

    private var eye: some View {
        Capsule()
            .fill(Color.bpInk.opacity(0.85))
            .frame(width: size * 0.05, height: blinking ? size * 0.01 : size * 0.07)
            .animation(.easeInOut(duration: 0.1), value: blinking)
    }

    private var mouth: some View {
        let curve = config.expression.mouthCurve / 44 * size
        return Path { path in
            let w = size * 0.14
            path.move(to: CGPoint(x: -w / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: curve))
        }
        .stroke(Color.bpInk.opacity(0.8), style: StrokeStyle(lineWidth: max(1, size * 0.025), lineCap: .round))
        .frame(width: size * 0.14, height: size * 0.06)
    }

    @ViewBuilder private var hair: some View {
        if config.hairStyle != .bald {
            let h = size * config.hairStyle.heightFraction
            switch config.hairStyle {
            case .bald:
                EmptyView()
            case .mohawk:
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(config.hairColor.color)
                    .frame(width: size * 0.10, height: h)
                    .offset(y: -size * 0.40 - h / 2)
            default:
                Circle()
                    .trim(from: 0.52, to: 1.0)
                    .fill(config.hairColor.color)
                    .frame(width: size * 0.70, height: size * 0.70)
                    .offset(y: -size * 0.14 - h * 0.3)
                    .frame(height: size * 0.30 + h * 0.3)
                    .clipped()
            }
        }
    }

    @ViewBuilder private var accessory: some View {
        switch config.accessory {
        case .none:
            EmptyView()
        case .sunglasses:
            Image(systemName: "sunglasses.fill")
                .font(.system(size: size * 0.26))
                .foregroundStyle(Color.bpInk)
                .offset(y: -size * 0.08)
        case .cap:
            Capsule()
                .fill(config.outfitColor.color.opacity(0.9))
                .frame(width: size * 0.56, height: size * 0.18)
                .offset(y: -size * 0.38)
        case .bucketHat:
            Capsule()
                .fill(config.outfitColor.color.opacity(0.9))
                .frame(width: size * 0.62, height: size * 0.20)
                .offset(y: -size * 0.36)
        case .chain:
            Circle()
                .stroke(Color.bpAmber, lineWidth: max(1, size * 0.03))
                .frame(width: size * 0.22, height: size * 0.10)
                .offset(y: size * 0.20)
        case .earring:
            Circle()
                .fill(Color.bpAmber)
                .frame(width: size * 0.05, height: size * 0.05)
                .offset(x: size * 0.28, y: -size * 0.02)
        }
    }

    private func scheduleBlink() {
        guard animated else { return }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 2_000_000_000...5_000_000_000))
                blinking = true
                try? await Task.sleep(nanoseconds: 120_000_000)
                blinking = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AvatarView(name: "Sebastian H", avatarUrl: nil, avatarConfig: .default, size: 90, animated: true)
        AvatarView(name: "Sebastian H", avatarUrl: nil, avatarConfig: .random(), size: 60, animated: true)
        AvatarView(name: "Sebastian H", avatarUrl: nil, avatarConfig: nil, size: 44)
    }
    .padding()
    .background(Color.bpSurface)
}
