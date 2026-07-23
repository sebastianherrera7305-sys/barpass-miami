import SwiftUI

/// The single branded frame every share card renders inside. Not a static
/// image — a real SwiftUI view, rasterized on demand by `ShareManager` via
/// `ImageRenderer`, so the exact same layout/branding is reused for every
/// content type instead of each screen inventing its own share graphic.
struct ShareCardView: View {
    enum Kind {
        case trip(title: String, city: String, dateRange: String, memberCount: Int)
        case venue(name: String, neighborhood: String, tag: String?, rating: Double)
        case pass(venueName: String, code: String)
        case referral(inviteCode: String)
    }

    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BarPassLogo()

            switch kind {
            case .trip(let title, let city, let dateRange, let memberCount):
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(2)
                metaRow(icon: "mappin.and.ellipse", text: city)
                metaRow(icon: "calendar", text: dateRange)
                if memberCount > 0 {
                    metaRow(icon: "person.2.fill", text: "\(memberCount)")
                }

            case .venue(let name, let neighborhood, let tag, let rating):
                Text(name)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(2)
                metaRow(icon: "mappin.and.ellipse", text: neighborhood)
                if let tag {
                    metaRow(icon: "sparkles", text: tag)
                }
                metaRow(icon: "star.fill", text: String(format: "%.1f", rating))

            case .pass(let venueName, let code):
                Text(venueName)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(2)
                metaRow(icon: "qrcode", text: code)

            case .referral(let inviteCode):
                Text("Miami, at its best.")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                metaRow(icon: "ticket.fill", text: inviteCode)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 360, height: 260, alignment: .topLeading)
        .background(Color.bpCardBackground)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.bpAmber.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.bpTextSecondary)
        }
    }
}
