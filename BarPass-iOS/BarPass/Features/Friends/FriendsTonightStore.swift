import SwiftUI
import CoreLocation

/// "Which of my friends are out right now, and where."
///
/// The store holds nothing sensitive of its own: every row came from
/// `get_friends_out_tonight()`, which only returns friends who are
/// mutually accepted, not blocked, have location sharing ON, and are
/// inside the night still in progress at the venue's own timezone (the
/// same 6 AM boundary stories use). It also returns nothing at all unless
/// the caller shares too — sharing is reciprocal — which is why
/// `needsSharingOptIn` exists instead of a bare empty list.
@MainActor
final class FriendsTonightStore: ObservableObject {
    static let shared = FriendsTonightStore()

    @Published private(set) var friends: [FriendPresence] = []
    @Published private(set) var isLoading = false
    /// True when the user's own sharing toggle is off, which is the reason
    /// the list is empty. Distinguishing this from "nobody is out" is the
    /// difference between a clear screen and a feature that looks broken.
    @Published private(set) var needsSharingOptIn = false

    private var lastLoad: Date?

    private init() {}

    /// Cheap to call from `.task` on any screen: refuses to re-hit the
    /// network more than once a minute.
    func refresh(force: Bool = false) async {
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < 60 { return }
        isLoading = true
        defer { isLoading = false }
        let sharing = (try? await RepositoryDependencies.friends.locationSharingEnabled()) ?? false
        needsSharingOptIn = !sharing
        guard sharing else {
            friends = []
            lastLoad = Date()
            return
        }
        friends = (try? await RepositoryDependencies.friends.friendsOutTonight()) ?? []
        lastLoad = Date()
    }

    /// Friends currently at one venue — what a map pin needs.
    func friends(atVenue venueId: String) -> [FriendPresence] {
        friends.filter { $0.venueId == venueId }
    }

    /// Distinct venues with at least one friend inside, for map markers.
    var venues: [FriendVenueGroup] {
        Dictionary(grouping: friends, by: { $0.venueId })
            .map { FriendVenueGroup(venueId: $0.key, people: $0.value) }
            .sorted { $0.people.count > $1.people.count }
    }
}

struct FriendVenueGroup: Identifiable, Sendable {
    let venueId: String
    let people: [FriendPresence]

    var id: String { venueId }
    var venueName: String { people.first?.venueName ?? "" }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: people.first?.venueLat ?? 0,
            longitude: people.first?.venueLng ?? 0
        )
    }
}

/// The map pin: overlapping avatars plus a count, so a venue with three
/// friends inside reads at a glance without tapping.
struct FriendsAtVenueMarker: View {
    let group: FriendVenueGroup

    var body: some View {
        HStack(spacing: -10) {
            ForEach(group.people.prefix(3)) { person in
                FriendAvatar(name: person.name, url: person.avatarUrl, size: 30)
            }
            if group.people.count > 3 {
                Text("+\(group.people.count - 3)")
                    .font(.bpScaled(11, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 30, height: 30)
                    .background(Color.bpAmber, in: Circle())
            }
        }
        .padding(4)
        .background(Color.bpCardBackground.opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bpAmber, lineWidth: 2))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .bpAccessibility(label: "\(group.people.count) · \(group.venueName)")
    }
}

/// The horizontal strip shown above the map — "who's out tonight", or the
/// one-line reason the strip is empty. Tapping a face centres the map on
/// that venue.
struct FriendsTonightStrip: View {
    @ObservedObject var store: FriendsTonightStore
    @ObservedObject private var l10n = L10n.shared
    var onSelect: (FriendPresence) -> Void
    /// ExploreView is not inside a NavigationStack (MainTabView switches
    /// raw views), so this opens the friends screen through the host
    /// instead of a NavigationLink that would silently do nothing.
    var onOpenFriends: () -> Void

    var body: some View {
        if store.needsSharingOptIn {
            Button(action: onOpenFriends) {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(Color.bpAmber)
                    Text(l10n.t("friends.tonight.sharingOff"))
                        .font(.bpScaled(11))
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
            }
            .buttonStyle(.plain)
        } else if !store.friends.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("friends.tonight.title").uppercased())
                    .font(.bpScaled(10, weight: .heavy))
                    .foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.friends) { person in
                            Button {
                                BPHaptics.light()
                                onSelect(person)
                            } label: {
                                VStack(spacing: 4) {
                                    FriendAvatar(name: person.name, url: person.avatarUrl, size: 44)
                                    Text(person.name)
                                        .font(.bpScaled(10, weight: .semibold))
                                        .foregroundStyle(Color.bpInk)
                                        .lineLimit(1)
                                    Text(person.venueName)
                                        .font(.bpScaled(9))
                                        .foregroundStyle(Color.bpTextSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 66)
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(
                                label: "\(person.name) · \(person.venueName)",
                                hint: l10n.t("friends.tonight.hint"),
                                isButton: true
                            )
                        }
                    }
                }
            }
        }
    }
}
