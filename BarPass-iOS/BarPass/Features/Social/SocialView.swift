import SwiftUI

/// The social home: your people, and what they're doing tonight.
///
/// This tab exists because of a structural problem named on 2026-09-15: 55
/// screens behind 5 tabs, with friends, chat and hosting buried three taps
/// deep in Profile next to "Delete account". Nothing that makes BarPass a
/// social app had a home — friends lived in settings, who's-out lived on the
/// map, and a fraternity chapter hung off a card in the feed. Four expressions
/// of one idea in four places, so none of them read as the same product.
///
/// The ordering is the argument: people first, because a social app opens on
/// people; then the rooms those people are in. Nothing here is a setting.
struct SocialView: View {
    @ObservedObject private var l10n = L10n.shared
    /// The shared store, not a second instance: Explore already drives one,
    /// and two would double the requests and disagree with each other.
    @ObservedObject private var tonight = FriendsTonightStore.shared

    @State private var hasChapter = false
    @State private var loadedAffiliation = false
    @State private var showFriends = false

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: BPSpacing.xl) {
                        outTonightSection
                        peopleSection
                        roomsSection
                    }
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.top, BPSpacing.md)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle(l10n.t("tab.social"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showFriends) { FriendsListView() }
            .task {
                await tonight.refresh()
                await loadAffiliation()
            }
        }
    }

    // MARK: - Who's out

    /// The one question no other app answers. It leads even when empty — an
    /// empty state that explains itself teaches the feature, while hiding the
    /// section until it has data means nobody learns it exists.
    private var outTonightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(l10n.t("social.outTonight"))
            if tonight.friends.isEmpty {
                emptyCard(
                    icon: "moon.stars.fill",
                    title: l10n.t("social.outTonight.emptyTitle"),
                    body: tonight.needsSharingOptIn
                        ? l10n.t("social.outTonight.emptyNotSharing")
                        : l10n.t("social.outTonight.emptyNobody"))
            } else {
                // Unlike Explore, this screen IS inside a NavigationStack, so
                // both callbacks can push properly.
                FriendsTonightStrip(store: tonight,
                                    onSelect: { _ in },
                                    onOpenFriends: { showFriends = true })
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(l10n.t("social.people"))
            NavigationLink { FriendsListView() } label: {
                rowCard(icon: "person.2.fill",
                        title: l10n.t("social.friends"),
                        subtitle: l10n.t("social.friends.sub"))
            }
            .buttonStyle(.plain)
        }
    }

    /// A chapter and a night you are hosting are both "a room with people in
    /// it". They sit together for that reason, not as leftovers.
    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(l10n.t("social.rooms"))

            NavigationLink { HostEventsListView() } label: {
                rowCard(icon: "sparkles",
                        title: l10n.t("social.hosting"),
                        subtitle: l10n.t("social.hosting.sub"))
            }
            .buttonStyle(.plain)

            if let city = SelectedCityStore.selectedCity {
                NavigationLink { UniversityListView(city: city) } label: {
                    rowCard(icon: "graduationcap.fill",
                            title: l10n.t("social.greek"),
                            subtitle: loadedAffiliation && hasChapter
                                ? l10n.t("social.greek.subMember")
                                : l10n.t("social.greek.sub"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.bpCaption())
            .foregroundStyle(Color.bpTextSecondary)
            .textCase(.uppercase)
    }

    private func rowCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.bpScaled(18))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bpHeadline()).foregroundStyle(Color.bpInk)
                Text(subtitle).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpTextTertiary)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: title, hint: subtitle, isButton: true)
    }

    private func emptyCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.bpScaled(20)).foregroundStyle(Color.bpAmber)
            Text(title).font(.bpHeadline()).foregroundStyle(Color.bpInk)
            Text(body).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private func loadAffiliation() async {
        if let a = try? await RepositoryDependencies.profileAffiliation.getAffiliation() {
            hasChapter = a.chapterId != nil
        }
        loadedAffiliation = true
    }
}
