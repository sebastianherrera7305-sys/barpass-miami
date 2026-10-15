import SwiftUI
import CoreLocation

// Tonight v17.1 hero: compact brand header + Remy's swipe deck + prompt bar.
// Everything below the hero (Hype, moods, rails) is untouched TonightView.

// MARK: - Brand header

struct TonightBrandHeader: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var friendsTonight = FriendsTonightStore.shared
    let city: String
    let openCount: Int
    let displayName: String?
    let greeting: String

    private var friendsOut: Int {
        Set(friendsTonight.friends.map(\.venueId)).isEmpty ? 0 : friendsTonight.friends.count
    }

    var body: some View {
        HStack(spacing: 10) {
            Image("BarPassMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Text("BAR").foregroundStyle(Color.bpInk)
                    Text("PASS").foregroundStyle(Color.bpAmber)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.bpAmber).frame(height: 2).offset(y: 2)
                        }
                }
                .font(.system(size: 19, weight: .black, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(Color.bpAmber).frame(width: 5, height: 5)
                        .shadow(color: Color.bpAmber, radius: 4)
                    Text("\(city.uppercased()) · LIVE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(greeting + ",")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.7))
                Text(displayName?.split(separator: " ").first.map(String.init) ?? "")
                    .font(.system(size: 26, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 3) {
                    Text(String(format: l10n.t("tonight.header.open"), openCount))
                    if friendsOut > 0 {
                        Text("·")
                        Text(String(format: l10n.t("tonight.header.friendsOut"), friendsOut))
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.bpInk.opacity(0.55))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 70)
        .background(Color(red: 0.04, green: 0.024, blue: 0.047).opacity(0.58), in: RoundedRectangle(cornerRadius: 20))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
        .bpAccessibility(label: "BarPass \(city). \(greeting)")
    }
}

// MARK: - Swipe deck

struct RemySwipeDeck: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var location = UserLocationProvider.shared
    @ObservedObject private var friendsTonight = FriendsTonightStore.shared
    let venues: [BarPassVenue]

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var flyingOut: CGFloat = 0
    @State private var selectedID: String?

    private let threshold: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(l10n.t("tonight.deck.eyebrow"), systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                Text("\(min(index + 1, max(venues.count, 1))) / \(venues.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.bpInk.opacity(0.65))
            }

            // Build 125 (owner report Build 124 "las tarjetas se salen y
            // quedan encima de mi nombre"): the back cards are rendered
            // with `.offset(y: -depth * 10)` which lifts them 10 and 20pt
            // UP visually — but `.offset` is a visual transform, not a
            // layout change, so the ZStack's reserved frame stays at
            // 300pt and the back cards poke above its top edge, into
            // whatever renders directly above (here, the greeting
            // "Buenas noches, <name>"). A 24pt top padding reserves the
            // room the stacked cards actually need; the ZStack now
            // measures 324pt total, back cards sit inside it, and the
            // greeting above never gets overlapped.
            ZStack {
                if index >= venues.count {
                    emptyState
                } else {
                    ForEach(Array(venues.enumerated().filter { $0.offset >= index && $0.offset < index + 3 }).reversed(), id: \.element.id) { offset, venue in
                        let depth = offset - index
                        card(for: venue, depth: depth)
                    }
                }
            }
            .frame(height: 300)
            .padding(.top, 24)

            HStack(spacing: 14) {
                actionButton(color: Color.bpDanger, label: l10n.t("tonight.deck.pass"), icon: {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .black)).foregroundStyle(Color.bpDanger)
                }) {
                    guard index < venues.count else { return }
                    pass()
                }
                Spacer()
                dots
                Spacer()
                actionButton(color: Color.bpAmber, label: l10n.t("tonight.deck.add"), icon: {
                    HeartEyes(fill: Color.bpAmber).frame(width: 30, height: 27)
                }) {
                    guard index < venues.count else { return }
                    accept(venues[index])
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationDestination(item: $selectedID) { id in
            if let venue = venues.first(where: { $0.id == id }) {
                VenueDetailView(venue: venue)
            }
        }
    }

    private func actionButton<Icon: View>(color: Color, label: String, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 54, height: 54)
                .background(Color.black.opacity(0.6), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.55), lineWidth: 1.5))
                .shadow(color: color.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, isButton: true)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(venues.count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.bpAmber : Color.white.opacity(0.25))
                    .frame(width: i == index ? 14 : 5, height: 5)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image("BarPassMascot").resizable().scaledToFit().frame(width: 64)
            Text(l10n.t("tonight.deck.empty"))
                .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
            Button(l10n.t("tonight.deck.again")) { withAnimation(.spring) { index = 0 } }
                .font(.bpCaption()).foregroundStyle(Color.bpAmber)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bpCardBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func card(for venue: BarPassVenue, depth: Int) -> some View {
        let isTop = depth == 0
        let x = isTop ? drag.width + flyingOut : 0
        let rotation = isTop ? Double(x / 18) : 0
        RemyDeckCard(
            venue: venue,
            distanceText: distanceText(venue),
            friendsInside: friendsTonight.friends.filter { $0.venueId == venue.id }.count,
            acceptProgress: isTop ? max(0, min(1, x / threshold)) : 0,
            passProgress: isTop ? max(0, min(1, -x / threshold)) : 0
        )
        .scaleEffect(1 - CGFloat(depth) * 0.04)
        .offset(x: x, y: CGFloat(-depth) * 10)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .opacity(depth == 2 ? 0.55 : 1)
        .zIndex(Double(3 - depth))
        .gesture(isTop ? dragGesture(venue) : nil)
        .onTapGesture { if isTop && abs(drag.width) < 4 { selectedID = venue.id } }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
    }

    private func dragGesture(_ venue: BarPassVenue) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let dx = value.translation.width
                if dx > threshold {
                    accept(venue)
                } else if dx < -threshold {
                    pass()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func accept(_ venue: BarPassVenue) {
        BPHaptics.success()
        if !favorites.isFavorite(venue.id) { favorites.toggle(venue.id) }
        fly(direction: 1)
    }

    private func pass() {
        BPHaptics.light()
        fly(direction: -1)
    }

    private func fly(direction: CGFloat) {
        withAnimation(.easeIn(duration: 0.22)) { flyingOut = direction * 520 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 230_000_000)
            index += 1
            drag = .zero
            flyingOut = 0
        }
    }

    private func distanceText(_ venue: BarPassVenue) -> String? {
        guard let c = location.coordinate else { return nil }
        let meters = CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: venue.latitude, longitude: venue.longitude))
        let miles = meters / 1609.344
        return miles < 10 ? String(format: "%.1f mi", miles) : nil
    }
}

// MARK: - Deck card

struct RemyDeckCard: View {
    @ObservedObject private var l10n = L10n.shared
    let venue: BarPassVenue
    let distanceText: String?
    let friendsInside: Int
    let acceptProgress: CGFloat
    let passProgress: CGFloat

    private var reason: String? {
        ExperienceScorer.reason(
            venue: venue,
            passport: MusicProfileStore.shared.passport,
            context: TripContext(),
            now: Date(),
            userCoordinate: UserLocationProvider.shared.coordinate
        )
    }

    private var statusText: String {
        let close = venue.closeTime
        let open = venue.openTime
        if venue.isOpenNow {
            return close.isEmpty ? l10n.t("tonight.deck.openNow") : String(format: l10n.t("tonight.deck.closes"), close)
        }
        return open.isEmpty ? l10n.t("tonight.deck.closed") : String(format: l10n.t("tonight.deck.opens"), open)
    }

    private var nameParts: (String, String) {
        let words = venue.name.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last else { return (venue.name, "") }
        return (words.dropLast().joined(separator: " "), last)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(red: 0.04, green: 0.2, blue: 0.27), Color(red: 0.07, green: 0.04, blue: 0.12), Color(red: 0.1, green: 0.04, blue: 0.17)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 22)
                .fill(RadialGradient(colors: [Color.bpAmber.opacity(0.28), .clear], center: .init(x: 0.86, y: 0.12), startRadius: 0, endRadius: 220))

            // Build 110 complaint: "card roto no tiene image". The old
            // CachedImage path only rendered when `photoUrls.first` existed,
            // leaving the ~41 photoless venues with just the dark base
            // gradient visible — the owner called those "roto". Rerouted
            // through VenueArtwork so the fallback chain (venue_media
            // cover → image_url → VenueLogos → tinted gradient with emoji)
            // ALWAYS produces something visible, matching the "imposible
            // que falte el logo o la foto" rule.
            VenueArtwork(
                venue: venue,
                targetSize: CGSize(width: 600, height: 500),
                titleScale: .hero,
                withBottomScrim: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .opacity(0.9)

            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)], startPoint: .init(x: 0.5, y: 0.25), endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            // live row
            VStack {
                HStack {
                    if let genre = venue.musicGenres.first {
                        HStack(spacing: 7) {
                            EqualizerBars()
                            Text(String(format: l10n.t("tonight.deck.playing"), genre.rawValue))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    }
                    Spacer()
                    if friendsInside > 0 {
                        Text(String(format: l10n.t("tonight.deck.inside"), friendsInside))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                Spacer()
            }

            // stamps
            stamp(l10n.t("tonight.deck.pass"), color: Color.bpDanger, rotation: -12, progress: passProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 72).padding(.leading, 18)
            stamp(l10n.t("tonight.deck.add"), color: Color.bpAmber, rotation: 12, progress: acceptProgress, heart: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 72).padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusText)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(venue.isOpenNow ? Color.bpAmber : Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))

                Text("\(venue.type.displayName) · \(venue.neighborhood)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(2).textCase(.uppercase)
                    .foregroundStyle(Color.bpAmber)

                (Text(nameParts.0 + (nameParts.1.isEmpty ? "" : " "))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                 + Text(nameParts.1)
                    .font(.system(size: 34, design: .serif).italic())
                    .foregroundColor(Color.bpAmberBright))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 3)

                HStack(spacing: 8) {
                    if let tier = venue.priceTier.symbol {
                        chip(tier, hot: true)
                    }
                    ForEach(venue.musicGenres.prefix(2), id: \.self) { g in chip(g.rawValue, hot: false) }
                    if venue.rating > 0 { chip(String(format: "★ %.1f", venue.rating), hot: false) }
                    Spacer()
                    if let distanceText {
                        Text(distanceText).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }

                if let reason {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.bpAmber).frame(width: 2, height: 16)
                        (Text("Remy: ").foregroundColor(Color.bpAmber).bold() + Text(reason))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 14)
        .bpAccessibility(label: venue.name, hint: reason ?? statusText, isButton: true)
    }

    private func chip(_ text: String, hot: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(hot ? .black : .white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hot ? Color.bpAmber : Color.white.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(hot ? 0 : 0.14)))
    }

    private func stamp(_ text: String, color: Color, rotation: Double, progress: CGFloat, heart: Bool = false) -> some View {
        HStack(spacing: 6) {
            if heart { HeartEyes(fill: color).frame(width: 24, height: 22) }
            Text(text)
                .font(.system(size: 20, weight: .black, design: .rounded)).textCase(.uppercase).tracking(1)
        }
            .foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(rotation))
            .opacity(Double(progress))
    }
}

/// Five bars that breathe — "2D pero dinámico". Static with Reduce Motion.
struct EqualizerBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let base: [CGFloat] = [0.6, 1, 0.45, 0.85, 0.55]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let phase = reduceMotion ? 1 : 0.55 + 0.45 * abs(sin(t * 3.2 + Double(i) * 0.9))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.bpAmber)
                        .frame(width: 3, height: 14 * base[i] * phase)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

// MARK: - Prompt bar

struct RemyPromptBarLabel: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.bpAmber).font(.system(size: 15))
            Text(l10n.t("tonight.prompt.placeholder"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.bpInk.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [Color.bpAmberBright, Color.bpAmber], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.bpAmber.opacity(0.35), radius: 8, y: 3)
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 48)
        .background(Color(red: 0.05, green: 0.03, blue: 0.03).opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1)))
        .bpAccessibility(label: l10n.t("tonight.remy.title"), hint: l10n.t("tonight.prompt.placeholder"), isButton: true)
    }
}

// MARK: - Heart with eyes (brand sticker — a heart that watches the night)

struct HeartShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.98))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.32), control1: CGPoint(x: w * 0.18, y: h * 0.78), control2: CGPoint(x: 0, y: h * 0.58))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.18), control1: CGPoint(x: 0, y: h * 0.02), control2: CGPoint(x: w * 0.36, y: h * -0.02))
        p.addCurve(to: CGPoint(x: w, y: h * 0.32), control1: CGPoint(x: w * 0.64, y: h * -0.02), control2: CGPoint(x: w, y: h * 0.02))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.98), control1: CGPoint(x: w, y: h * 0.58), control2: CGPoint(x: w * 0.82, y: h * 0.78))
        p.closeSubpath()
        return p
    }
}

struct HeartEyes: View {
    var fill: Color = .bpAmber
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                HeartShape().fill(fill)
                HStack(spacing: w * 0.1) {
                    eye(w: w * 0.26, h: h * 0.24)
                    eye(w: w * 0.26, h: h * 0.24)
                }
                .offset(y: -h * 0.1)
            }
        }
    }
    private func eye(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(.white)
            Ellipse().fill(.black).frame(width: w * 0.55, height: h * 0.72).offset(x: w * 0.06, y: h * 0.04)
        }
        .frame(width: w, height: h)
    }
}
