import SwiftUI
import UIKit

/// The single entry point for every "share" action in the app — trips,
/// venues, passes, reservations, tickets, and (infra-only for now) referral.
/// Consolidates what used to be 5 independent implementations, 3 of them
/// duplicating their own `topVC` window lookup and 2 of them bypassing
/// L10n entirely (see PHASE_1_SHAREMANAGER_AUDIT.md).
///
/// `DeepLinkRouter` remains the only thing that ever *reads* a barpass://
/// URL — ShareManager only ever *builds* one, and only in the exact shapes
/// DeepLinkRouter already knows how to parse (`trip/{id}`, `venue/{id}`).
@MainActor
enum ShareManager {
    struct Content {
        let text: String
        let url: URL?
        let cardImage: UIImage?
    }

    // MARK: - Content builders

    static func shareTrip(_ trip: Trip) -> Content {
        let text = String(format: L10n.shared.t("tripDetail.invite.shareText"), trip.title, trip.inviteCode ?? "")
        // No web landing page exists yet for trips (barpass-v2 has no
        // /trip/[id] route — confirmed in the audit). Using the custom
        // scheme only avoids repeating the exact "broken web URL" bug just
        // fixed for venues; it resolves for anyone who already has the app,
        // and is a documented limitation until the web landing (S3) exists.
        let url = URL(string: "barpass://trip/\(trip.id)")
        let card = renderCard(.trip(
            title: trip.title,
            city: trip.destinationCity,
            dateRange: formattedRange(trip.startDate, trip.endDate),
            memberCount: trip.memberIds.count
        ))
        return Content(text: text, url: url, cardImage: card)
    }

    static func shareVenue(_ venue: BarPassVenue) -> Content {
        let text = String(format: L10n.shared.t("venueDetail.shareText"), venue.name, venue.neighborhood)
        // Prefer the real web page (works for anyone, browser or not) when
        // the venue actually has a slug; fall back to the app-only deep
        // link rather than ever emitting the old `/venues/{id}` URL, which
        // 404s against the real Next.js route (keyed on slug, not id).
        let url: URL?
        if let slug = venue.slug, !slug.isEmpty {
            url = URL(string: "https://barpass.app/venues/\(slug)")
        } else {
            url = URL(string: "barpass://venue/\(venue.id)")
        }
        let card = renderCard(.venue(
            name: venue.name,
            neighborhood: venue.neighborhood,
            tag: venue.tags.first,
            rating: venue.rating
        ))
        return Content(text: text, url: url, cardImage: card)
    }

    static func sharePass(_ pass: SkipLinePass) -> Content {
        let text = String(format: L10n.shared.t("pass.shareText"), pass.venueName, pass.passCode)
        let card = renderCard(.pass(venueName: pass.venueName, code: pass.passCode))
        return Content(text: text, url: nil, cardImage: card)
    }

    static func shareReservation(_ reservation: TableReservation) -> Content {
        let text = String(
            format: L10n.shared.t("reservationConfirm.shareText"),
            reservation.venueName, reservation.confirmCode, reservation.formattedDate
        )
        return Content(text: text, url: nil, cardImage: nil)
    }

    static func shareTicket(_ ticket: EventTicket) -> Content {
        let text = String(
            format: L10n.shared.t("ticket.shareText"),
            ticket.eventName, ticket.venueName, ticket.formattedDate, ticket.ticketCode
        )
        return Content(text: text, url: nil, cardImage: nil)
    }

    /// Infrastructure only — no referral tracking/points/UI yet (that's a
    /// separate, not-yet-designed product decision). Produces a shareable
    /// card + link today so the plumbing exists ahead of that design.
    static func shareReferral(inviteCode: String) -> Content {
        let text = String(format: L10n.shared.t("referral.shareText"), inviteCode)
        let url = URL(string: "https://barpass.app")
        let card = renderCard(.referral(inviteCode: inviteCode))
        return Content(text: text, url: url, cardImage: card)
    }

    // MARK: - Presentation

    /// The one place in the app that presents a share sheet. Replaces the
    /// 3 duplicated `topVC`/window-lookup implementations that used to live
    /// in ReservationConfirmView, ActivePassView, and ActiveTicketView.
    static func present(_ content: Content) {
        var items: [Any] = [content.text]
        if let cardImage = content.cardImage { items.append(cardImage) }
        if let url = content.url { items.append(url) }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topViewController()?.present(activityVC, animated: true)
    }

    // MARK: - Private helpers

    private static func renderCard(_ kind: ShareCardView.Kind) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(kind: kind))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private static func formattedRange(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
    }
}
