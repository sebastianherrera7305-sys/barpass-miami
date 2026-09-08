import SwiftUI
import PhotosUI
import AVKit

/// Real photos/videos posted by anyone at the venue — "Factory Town" (an
/// event venue open only a handful of nights a year) is the trigger: the
/// user wants people posting from inside tonight's event, directly in the
/// app. Deliberately simple for a same-day ship (supabase/venue_media.sql):
/// picks from the photo library (whatever was just shot tonight already
/// lands there), no in-app camera, no moderation queue.
///
/// Media is compressed on-device before upload (720p / max 60s video,
/// 1600px JPEG photo) and sent in resumable chunks — see
/// SupabaseVenueMediaRepository for why a raw phone video never made it.
struct VenueMediaSection: View {
    let venue: BarPassVenue
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var uploader = VenueMediaUploader()
    @State private var items: [VenueMediaItem] = []
    @State private var isLoading = true
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var playingItem: VenueMediaItem?

    private let repo: VenueMediaRepository = RepositoryDependencies.venueMedia

    var body: some View {
        // Resolved here, not inside PhotosPicker's label closure — that
        // closure is nonisolated and can't touch main-actor state.
        let isBusy = uploader.isBusy
        let addTitle = l10n.t("venueMedia.add")
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l10n.t("venueMedia.title"))
                    .font(.bpTitle2()).foregroundStyle(Color.bpInk)
                Spacer()
                PhotosPicker(selection: $selectedPickerItem, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView().tint(.black).scaleEffect(0.7)
                        } else {
                            Image(systemName: "plus").font(.bpScaled(12, weight: .bold))
                        }
                        Text(addTitle).font(.bpScaled(13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.bpAmber, in: Capsule())
                }
                .disabled(isBusy)
                .bpAccessibility(label: l10n.t("venueMedia.add"), hint: l10n.t("venueMedia.add.hint"), isButton: true)
            }

            if let label = uploader.stageLabel(l10n) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                    ProgressView(value: uploader.stage == .uploading ? uploader.fraction : nil)
                        .tint(Color.bpAmber)
                }
            }

            if let uploadError = uploader.error {
                Text(uploadError).font(.bpCaption()).foregroundStyle(Color.bpDanger)
            }

            if isLoading {
                ShimmerSkeleton(height: 100)
                    .bpLoadingRegion(l10n.t("a11y.loading"))
            } else if items.isEmpty {
                VStack(spacing: 6) {
                    Text("📸").font(.bpScaled(30))
                    Text(l10n.t("venueMedia.empty"))
                        .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Color.bpInk.opacity(0.03), in: RoundedRectangle(cornerRadius: BPRadius.md))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            mediaThumbnail(item)
                        }
                    }
                }
            }
        }
        .task(id: venue.id) { await load() }
        .onChange(of: selectedPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let item = await uploader.upload(newItem, venueId: venue.id) {
                    withAnimation { items.insert(item, at: 0) }
                }
                selectedPickerItem = nil
            }
        }
        .sheet(item: $playingItem) { item in
            mediaViewer(item)
        }
    }


    private func mediaThumbnail(_ item: VenueMediaItem) -> some View {
        Button {
            BPHaptics.light()
            playingItem = item
        } label: {
            ZStack {
                AsyncImage(url: URL(string: item.mediaUrl)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color.bpSurfaceRaised
                            if item.mediaType == .video {
                                // Videos have no separate thumbnail (no
                                // server-side processing in this v1) — a
                                // clear placeholder beats a broken image.
                                Image(systemName: "video.fill").foregroundStyle(Color.bpTextSecondary)
                            } else {
                                ProgressView().tint(Color.bpAmber)
                            }
                        }
                    }
                }
                if item.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: BPRadius.md))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: item.mediaType == .video ? l10n.t("venueMedia.a11y.video") : l10n.t("venueMedia.a11y.photo"), isButton: true)
    }

    @ViewBuilder
    private func mediaViewer(_ item: VenueMediaItem) -> some View {
        if item.mediaType == .video, let url = URL(string: item.mediaUrl) {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
        } else if let url = URL(string: item.mediaUrl) {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: ProgressView().tint(.white)
                    }
                }
            }
        }
    }

    private func load() async {
        items = (try? await repo.media(for: venue.id)) ?? []
        withAnimation(.easeIn(duration: 0.2)) { isLoading = false }
    }
}
