import SwiftUI

/// Flyer-style event card (Posh/Dice-inspired): the venue's real photo as
/// full-bleed art, dark gradient, a big date block and the artist as the
/// headline. Turns "event = text row" into "event = poster".
struct EventFlyerCard: View {
    let event: VenueEvent
    let venue: BarPassVenue
    var width: CGFloat = 220
    var height: CGFloat = 290

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "MMM"; return f
    }()

    /// (label, background color) for the top-right status badge, or nil to
    /// hide it (far-out upcoming events don't need one — the date block
    /// already communicates that).
    private var statusBadge: (label: String, color: Color)? {
        switch VenueTimeStatus.status(for: event) {
        case .liveNow:
            return (l10n.t("event.badge.live"), Color.bpDanger)
        case .endingSoon(let mins):
            return (String(format: l10n.t("event.badge.endingSoon"), max(mins, 1)), Color.bpAmber)
        case .upcoming(let mins) where mins <= 60:
            return (String(format: l10n.t("event.badge.startsInMin"), mins), Color.bpAmber)
        case .upcoming(let mins) where mins <= 6 * 60:
            return (String(format: l10n.t("event.badge.startsInHours"), max(mins / 60, 1)), Color.bpAmber.opacity(0.85))
        case .upcoming, .finished:
            return nil
        }
    }

    var body: some View {
        Button {
            BPHaptics.light()
            appState.priorityVenueId = venue.id
            appState.priorityVenueName = venue.name
            appState.priorityEvent = event
            appState.showPriorityEntry = true
        } label: {
            card
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(
            label: String(format: l10n.t("event.card.a11y"), event.title, venue.name),
            hint: l10n.t("event.card.hint"),
            isButton: true
        )
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            // Art: real venue photo, clipped to the card (never expands layout).
            if let first = venue.photoUrls.first, let url = URL(string: first) {
                CachedImage(url: url, targetSize: CGSize(width: width * 2, height: height * 2), priority: .hot) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    LinearGradient(colors: [Color.bpAmber.opacity(0.25), Color.bpCardBackground],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            } else {
                LinearGradient(colors: [Color.bpAmber.opacity(0.25), Color.bpCardBackground],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }

            // Legibility gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.25), .black.opacity(0.92)],
                startPoint: .init(x: 0.5, y: 0.25), endPoint: .bottom
            )

            // Date block (top-left)
            VStack(spacing: 0) {
                Text(Self.day.string(from: event.date))
                    .font(.bpScaled(22, weight: .black))
                    .foregroundStyle(.white)
                Text(Self.month.string(from: event.date).uppercased())
                    .font(.bpScaled(10, weight: .bold))
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)

            // Live/starting-soon status badge (top-right)
            if let badge = statusBadge {
                Text(badge.label)
                    .font(.bpScaled(10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(badge.color, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }

            // Headline + venue
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.bpScaled(19, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(.white)
                        if let logo = VenueLogos.url(for: venue.id) {
                            CachedImage(url: logo, targetSize: CGSize(width: 40, height: 40), priority: .hot) { img in
                                img.resizable().scaledToFit().padding(3)
                            } placeholder: { Text(venue.emoji).font(.bpScaled(10)) }
                        } else { Text(venue.emoji).font(.bpScaled(10)) }
                    }
                    .frame(width: 20, height: 20).clipShape(Circle())

                    Text(venue.name)
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)

                    if let cover = event.coverPrice {
                        Text(cover == 0 ? "Gratis" : String(format: "$%.0f", cover))
                            .font(.bpScaled(11, weight: .bold))
                            .foregroundStyle(cover == 0 ? Color.bpGreen : Color.bpAmber)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }
}
