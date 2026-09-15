import SwiftUI

/// One person in the list. Which controls appear is driven entirely by
/// the server-supplied relation — an `incoming` row gets Accept/Decline,
/// a `friend` row gets a chat link, an `outgoing` row gets Cancel.
struct FriendRow: View {
    let edge: FriendEdge
    let hasUnread: Bool
    let onAccept: () -> Void
    let onRemove: () -> Void
    let onBlock: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(name: edge.name, url: edge.avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(edge.name)
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                Text(subtitle)
                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            controls
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .contextMenu {
            Button(l10n.t("friends.remove"), role: .destructive, action: onRemove)
            Button(l10n.t("friends.block"), role: .destructive, action: onBlock)
        }
    }

    private var subtitle: String {
        switch edge.relation {
        case .friend: return hasUnread ? l10n.t("friends.newMessage") : l10n.t("friends.relation.friend")
        case .incoming: return l10n.t("friends.relation.incoming")
        case .outgoing: return l10n.t("friends.relation.outgoing")
        case .none: return ""
        }
    }

    @ViewBuilder private var controls: some View {
        switch edge.relation {
        case .incoming:
            HStack(spacing: 8) {
                Button(l10n.t("friends.accept"), action: onAccept)
                    .font(.bpScaled(12, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.bpAmber, in: Capsule())
                    .bpAccessibility(label: l10n.t("friends.accept"), hint: edge.name, isButton: true)
                Button(l10n.t("friends.decline"), action: onRemove)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
                    .bpAccessibility(label: l10n.t("friends.decline"), hint: edge.name, isButton: true)
            }
            .buttonStyle(.plain)
        case .friend:
            NavigationLink {
                FriendChatView(friendId: edge.userId, friendName: edge.name)
            } label: {
                Image(systemName: hasUnread ? "bubble.left.fill" : "bubble.left")
                    .font(.bpScaled(18, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
            }
            .bpAccessibility(label: l10n.t("friends.chat"), hint: edge.name, isButton: true)
        case .outgoing:
            Button(l10n.t("friends.cancelRequest"), action: onRemove)
                .font(.bpScaled(12, weight: .semibold))
                .foregroundStyle(Color.bpTextSecondary)
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("friends.cancelRequest"), hint: edge.name, isButton: true)
        case .none:
            EmptyView()
        }
    }
}

/// Initials on an amber ring, or the avatar if the profile has one.
struct FriendAvatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                CachedImage(url: parsed, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsLabel
                }
            } else {
                initialsLabel
            }
        }
        .frame(width: size, height: size)
        .background(Color.bpSurface, in: Circle())
        .overlay(Circle().strokeBorder(Color.bpAmber.opacity(0.35)))
        .clipShape(Circle())
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.bpAmber)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
