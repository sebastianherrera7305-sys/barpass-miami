import SwiftUI

/// The crowd signal on a feed card. This is the whole point of the
/// feature: scrolling Tonight, the question is "where is everybody", and
/// this is the only element on the card that answers it with something
/// that happened in the last few hours rather than a Google rating from
/// 2019.
///
/// It says how many PEOPLE posted, not how many frames — `posterCount` is
/// distinct posters, so one person shooting ten clips still reads as one
/// person. And it never names them: the store is fed by
/// `public.venue_story_pulse`, which is a count and a thumbnail with no
/// author column at all.
struct VenueStoryBadge: View {
    let venueId: String
    /// Cards on a dark photo scrim must stay light; cards on the themed
    /// surface must not.
    var onDarkScrim: Bool = true

    @ObservedObject private var store = VenueStoryPulseStore.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let pulse = store.pulse(for: venueId), pulse.posterCount > 0 {
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.bpScaled(9, weight: .bold))
                Text("\(pulse.posterCount)")
                    .font(.bpScaled(11, weight: .heavy))
                Text(l10n.t("story.badge.tonight"))
                    .font(.bpTiny())
                    .tracking(1)
            }
            .foregroundStyle(onDarkScrim ? Color.bpAmberBright : Color.bpAmber)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (onDarkScrim ? Color.black.opacity(0.55) : Color.bpAmber.opacity(0.12)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
            .bpAccessibility(label: String(format: l10n.t("story.badge.a11y"), pulse.posterCount))
        }
    }
}

/// The venue-detail entry point: the night, playable.
///
/// One circle per PERSON (frames are grouped by `posterSeq`), which is
/// what makes eight photos read as three people's nights instead of a
/// tile grid — and is also the only reason `posterSeq` exists. There is no
/// name and no avatar under any circle, because the server never sends
/// one.
struct VenueStoriesStrip: View {
    let venue: BarPassVenue

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var pulseStore = VenueStoryPulseStore.shared
    @State private var stories: [VenueStory] = []
    @State private var isLoading = true
    @State private var viewerStart: Int?

    private let repository: VenueStoryRepository = RepositoryDependencies.venueStory

    /// The index into `stories` where each person's run begins.
    private var posterStarts: [PosterRun] {
        var seen = Set<Int>()
        var result: [PosterRun] = []
        for (i, story) in stories.enumerated() where !seen.contains(story.posterSeq) {
            seen.insert(story.posterSeq)
            result.append(PosterRun(seq: story.posterSeq, index: i))
        }
        return result
    }

    private var posterCount: Int { posterStarts.count }

    var body: some View {
        Group {
            if isLoading {
                ShimmerSkeleton(height: 84)
                    .bpLoadingRegion(l10n.t("a11y.loading"))
            } else if stories.isEmpty {
                // An empty night is a fact, not a failure — and saying so
                // is the invitation to be the first one to post.
                Text(l10n.t("story.empty"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
        .task(id: venue.id) { await load() }
        .fullScreenCover(item: Binding(
            get: { viewerStart.map(StoryStart.init(index:)) },
            set: { viewerStart = $0?.index }
        )) { start in
            StoryViewer(venueName: venue.name, stories: stories, startIndex: start.index) {
                viewerStart = nil
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: l10n.t(posterCount == 1 ? "story.header.one" : "story.header.many"), posterCount))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(posterStarts) { poster in
                        circle(for: poster)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func circle(for poster: PosterRun) -> some View {
        let story = stories[poster.index]
        return Button {
            BPHaptics.light()
            viewerStart = poster.index
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            LinearGradient(colors: [Color.bpAmberBright, Color.bpAmber],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2.5
                        )
                        .frame(width: 66, height: 66)

                    CachedImage(url: URL(string: story.mediaUrl),
                                targetSize: CGSize(width: 160, height: 160), priority: .hot) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Color.bpSurfaceRaised
                            if story.mediaType == .video {
                                Image(systemName: "video.fill")
                                    .foregroundStyle(Color.bpTextSecondary)
                            }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    if story.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.bpScaled(12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                }
                Text(StoryTime.ago(story.createdAt, l10n))
                    .font(.bpTiny())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .bpAccessibility(
            label: String(format: l10n.t("story.circle.a11y"), StoryTime.ago(story.createdAt, l10n)),
            hint: l10n.t("story.circle.hint"),
            isButton: true
        )
    }

    private func load() async {
        stories = (try? await repository.stories(for: venue.id)) ?? []
        pulseStore.refresh()
        withAnimation(.easeIn(duration: 0.2)) { isLoading = false }
    }
}

/// One person's run of frames inside tonight, addressed by the per-venue,
/// per-night sequence number the server assigns. Not a user id, and not
/// stable past 6am.
private struct PosterRun: Identifiable {
    let seq: Int
    let index: Int
    var id: Int { seq }
}

/// `fullScreenCover(item:)` needs an Identifiable; an Int index is not.
private struct StoryStart: Identifiable {
    let index: Int
    var id: Int { index }
}
