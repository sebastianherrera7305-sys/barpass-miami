import SwiftUI

/// The social home.
///
/// The first version of this screen was three sections of identical rows with
/// chevrons, and the verdict on it was exact: it looked like something an AI
/// made in five minutes. It was — it was a settings menu wearing a social
/// tab's name. Instagram, Snapchat and Facebook all open on the same two
/// things: faces, and something that just happened. Never on a list of links.
///
/// So this screen is content. A ring rail of the rooms people are posting
/// from, then one stream of what is actually going on: nights you can RSVP
/// to, friends who just walked into somewhere, rooms filling up. Friends and
/// hosting live in the toolbar, because they are places you occasionally go,
/// not the thing you came here to see.
///
/// Everything below is a real row from the database. There is no placeholder
/// content and no seeded activity — on a quiet Tuesday with nobody out this
/// screen is nearly empty, and that is the honest answer.
struct SocialView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var tonight = FriendsTonightStore.shared
    @ObservedObject private var pulse = VenueStoryPulseStore.shared
    @ObservedObject private var venueStore: VenueStore

    @State private var events: [HostEvent] = []
    @State private var openStories: StoryTarget?
    @State private var loadingStoriesFor: String?
    @State private var showFriends = false
    @State private var showHosting = false
    @State private var showSchools = false

    private let storyRepository: VenueStoryRepository = RepositoryDependencies.venueStory
    private let hostRepository = RepositoryDependencies.hostEvent

    init(venueStore: VenueStore) {
        _venueStore = ObservedObject(wrappedValue: venueStore)
    }

    // MARK: - Data

    /// Venues with live stories, busiest first — the rail is a ranking, so
    /// the room everyone is posting from sits on the left.
    private var rooms: [(venue: BarPassVenue, pulse: VenueStoryPulse)] {
        pulse.byVenue.values
            .sorted { $0.posterCount != $1.posterCount ? $0.posterCount > $1.posterCount : $0.latestAt > $1.latestAt }
            .compactMap { p in venueStore.venues.first { $0.id == p.venueId }.map { ($0, p) } }
    }

    /// One stream, newest first. An upcoming night carries its start time, so
    /// tonight's plans naturally rise above what already happened — which is
    /// the order you want at 9pm and still the right one at 2am.
    private var feed: [FeedItem] {
        var items: [FeedItem] = events.map { .night($0) }
        items += tonight.friends.map { .arrival($0) }
        items += rooms.filter { $0.pulse.posterCount > 1 }.map { .room($0.venue, $0.pulse) }
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !rooms.isEmpty { storyRail }
                        ForEach(feed) { item in
                            card(for: item)
                                .padding(.horizontal, BPSpacing.lg)
                        }
                        if feed.isEmpty { quietNight }
                        schoolCard
                            .padding(.horizontal, BPSpacing.lg)
                            .padding(.top, feed.isEmpty ? 0 : 10)
                    }
                    .padding(.top, BPSpacing.sm)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle(l10n.t("tab.social"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { BPHaptics.light(); showHosting = true } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Color.bpAmber)
                    }
                    .bpAccessibility(label: l10n.t("social.hosting"), isButton: true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { BPHaptics.light(); showFriends = true } label: {
                        Image(systemName: "person.2.fill").foregroundStyle(Color.bpAmber)
                    }
                    .bpAccessibility(label: l10n.t("social.friends"), isButton: true)
                }
            }
            .navigationDestination(isPresented: $showFriends) { FriendsListView() }
            .navigationDestination(isPresented: $showHosting) { HostEventsListView() }
            .navigationDestination(isPresented: $showSchools) {
                UniversityListView(city: venueStore.selectedCity ?? "")
            }
            .fullScreenCover(item: $openStories) { target in
                StoryViewer(venueName: target.venueName, stories: target.stories) {
                    openStories = nil
                }
            }
            .task { await load(force: false) }
            .refreshable { await load(force: true) }
        }
    }

    private func load(force: Bool) async {
        pulse.refresh(force: force)
        async let friends: Void = tonight.refresh(force: force)
        async let nights = (try? await hostRepository.events(venueId: nil, limit: 20)) ?? []
        _ = await friends
        events = await nights.filter { !$0.isCancelled }
    }

    // MARK: - Story rail

    /// Rings, because a ring reads as "there is something here to open" to
    /// anyone who has held a phone in the last decade. Borrowed on purpose:
    /// this is the one convention it would be perverse to reinvent.
    private var storyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rooms, id: \.venue.id) { item in
                    Button {
                        BPHaptics.light()
                        Task { await presentStories(at: item.venue) }
                    } label: {
                        VStack(spacing: 6) {
                            ring(for: item)
                            Text(item.venue.name)
                                .font(.bpScaled(11, weight: .semibold))
                                .foregroundStyle(Color.bpInk)
                                .lineLimit(1)
                                .frame(width: 74)
                        }
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(
                        label: item.venue.name,
                        hint: String(format: l10n.t("story.badge.a11y"), item.pulse.posterCount),
                        isButton: true)
                }
            }
            .padding(.horizontal, BPSpacing.lg)
            .padding(.top, 4)
        }
    }

    private func ring(for item: (venue: BarPassVenue, pulse: VenueStoryPulse)) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [Color.bpAmberBright, Color.bpAmber],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2.5)
                .frame(width: 74, height: 74)
            thumb(url: item.pulse.latestMediaUrl ?? item.venue.photoUrls.first,
                  fallback: item.venue.emoji, side: 64)
                .clipShape(Circle())
            if loadingStoriesFor == item.venue.id {
                Circle().fill(Color.black.opacity(0.5)).frame(width: 64, height: 64)
                ProgressView().tint(Color.bpAmber)
            }
        }
    }

    private func presentStories(at venue: BarPassVenue) async {
        loadingStoriesFor = venue.id
        defer { loadingStoriesFor = nil }
        let stories = (try? await storyRepository.stories(for: venue.id)) ?? []
        guard !stories.isEmpty else { return }
        openStories = StoryTarget(venueName: venue.name, stories: stories)
    }

    // MARK: - Feed cards

    @ViewBuilder private func card(for item: FeedItem) -> some View {
        switch item {
        case .night(let event):     nightCard(event)
        case .arrival(let friend):  arrivalCard(friend)
        case .room(let v, let p):   roomCard(v, p)
        }
    }

    /// A night someone is throwing. The cover image is the whole card,
    /// because a flyer is how this industry has announced a party since
    /// before any of us — a text row would throw away the only art a
    /// promoter ever makes.
    private func nightCard(_ event: HostEvent) -> some View {
        NavigationLink(destination: HostEventDetailView(eventId: event.id)) {
            ZStack(alignment: .bottomLeading) {
                thumb(url: event.coverImageUrl, fallback: "🎟️", side: nil)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.startsAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                        .font(.bpScaled(10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Color.bpAmberBright)
                    Text(event.title)
                        .font(.bpScaled(19, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let place = venueName(for: event) {
                        Text(place)
                            .font(.bpCaption())
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(14)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: event.title, hint: venueName(for: event) ?? "", isButton: true)
    }

    /// The API omits the venue name on some responses (it doesn't re-join
    /// the row), so fall back to the catalogue we already hold, and print
    /// nothing rather than a guess when neither knows it.
    private func venueName(for event: HostEvent) -> String? {
        if let name = event.venue.name, !name.isEmpty { return name }
        return venueStore.venues.first { $0.id == event.venue.id }?.name
    }

    /// Someone you know walked into somewhere. The face is the content.
    private func arrivalCard(_ friend: FriendPresence) -> some View {
        let venue = venueStore.venues.first { $0.id == friend.venueId }
        return HStack(spacing: 12) {
            FriendAvatar(name: friend.name, url: friend.avatarUrl, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                (Text(friend.name).font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                 + Text("  ") 
                 + Text(l10n.t("social.feed.isAt")).font(.bpScaled(14)).foregroundStyle(Color.bpTextSecondary)
                 + Text("  ")
                 + Text(friend.venueName).font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpAmber))
                    .lineLimit(2)
                Text(ago(friend.checkedInAt))
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextTertiary)
            }
            Spacer(minLength: 0)
            if let venue {
                thumb(url: venue.photoUrls.first, fallback: venue.emoji, side: 50)
                    .clipShape(RoundedRectangle(cornerRadius: BPRadius.md))
            }
        }
        .bpAccessibility(label: "\(friend.name), \(friend.venueName)")
    }

    /// A room filling up: several different people posting from the same
    /// place inside the same night. `posterCount` is distinct people, never
    /// frames, and the server sends no author for any of them.
    private func roomCard(_ venue: BarPassVenue, _ p: VenueStoryPulse) -> some View {
        Button {
            BPHaptics.light()
            Task { await presentStories(at: venue) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                thumb(url: p.latestMediaUrl ?? venue.photoUrls.first, fallback: venue.emoji, side: nil)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(venue.name)
                        .font(.bpScaled(19, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(String(format: l10n.t(p.posterCount == 1 ? "story.header.one" : "story.header.many"),
                                p.posterCount))
                        .font(.bpCaption())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(14)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: venue.name,
                         hint: String(format: l10n.t("story.badge.a11y"), p.posterCount),
                         isButton: true)
    }

    /// The college door. It stays on this screen because 20 of our 23 cities
    /// are college towns, but it is a picture of a campus night, not a row
    /// with a chevron.
    private var schoolCard: some View {
        Button {
            BPHaptics.light()
            showSchools = true
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("social.greek"))
                        .font(.bpScaled(17, weight: .black))
                        .foregroundStyle(Color.bpInk)
                    Text(l10n.t("social.greek.sub"))
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "graduationcap.fill")
                    .font(.bpScaled(30))
                    .foregroundStyle(Color.bpAmber.opacity(0.8))
            }
            .padding(16)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
        }
        .buttonStyle(.plain)
    }

    /// Nobody out is the normal state of a Tuesday, and of a product with
    /// eleven users. It should read like a quiet night, not like a bug.
    private var quietNight: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("social.outTonight.emptyTitle"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
            Text(tonight.needsSharingOptIn
                 ? l10n.t("social.outTonight.emptyNotSharing")
                 : l10n.t("social.outTonight.emptyNobody"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
            Button {
                BPHaptics.medium(); showFriends = true
            } label: {
                Text(l10n.t("social.friends"))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BPSpacing.lg)
        .padding(.top, 30)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func thumb(url: String?, fallback: String, side: CGFloat?) -> some View {
        let box = side.map { CGSize(width: $0 * 2, height: $0 * 2) } ?? CGSize(width: 900, height: 620)
        Group {
            if let url, let parsed = URL(string: url) {
                CachedImage(url: parsed, targetSize: box, priority: .hot) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.bpCardBackground.overlay(ShimmerSkeleton(height: side ?? 210).opacity(0.5))
                }
            } else {
                Color.bpCardBackground.overlay(Text(fallback).font(.bpScaled(side == nil ? 40 : 22)))
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    /// The same three buckets the story viewer uses, so "2h ago" means the
    /// same thing everywhere in the app.
    private func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return l10n.t("story.ago.now") }
        if seconds < 3600 { return String(format: l10n.t("story.ago.minutes"), seconds / 60) }
        return String(format: l10n.t("story.ago.hours"), seconds / 3600)
    }
}

// MARK: - Feed model

private enum FeedItem: Identifiable {
    case night(HostEvent)
    case arrival(FriendPresence)
    case room(BarPassVenue, VenueStoryPulse)

    var id: String {
        switch self {
        case .night(let e):     return "n-\(e.id)"
        case .arrival(let f):   return "a-\(f.userId)"
        case .room(let v, _):   return "r-\(v.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .night(let e):     return e.startsAt
        case .arrival(let f):   return f.checkedInAt
        case .room(_, let p):   return p.latestAt
        }
    }
}

/// `fullScreenCover(item:)` needs one Identifiable payload, and the viewer
/// needs the venue's name plus its already-loaded frames.
private struct StoryTarget: Identifiable {
    let venueName: String
    let stories: [VenueStory]
    var id: String { stories.first?.id ?? venueName }
}
