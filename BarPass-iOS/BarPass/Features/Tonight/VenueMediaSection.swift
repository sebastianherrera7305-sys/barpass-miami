import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

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
    @StateObject private var uploadState = UploadState()
    @State private var items: [VenueMediaItem] = []
    @State private var isLoading = true
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var uploadError: String?
    @State private var playingItem: VenueMediaItem?

    private let repo: VenueMediaRepository = RepositoryDependencies.venueMedia

    /// Longer clips are trimmed to this before upload — keeps a 720p clip
    /// around 20-30MB, under Supabase's 50MB object cap with room to spare.
    static let maxVideoSeconds: Double = 60

    var body: some View {
        // Resolved here, not inside PhotosPicker's label closure — that
        // closure is nonisolated and can't touch main-actor state.
        let isBusy = uploadState.stage != nil
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

            if let stage = uploadState.stage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stageLabel(stage))
                        .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                    ProgressView(value: stage == .uploading ? uploadState.fraction : nil)
                        .tint(Color.bpAmber)
                }
            }

            if let uploadError {
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
            Task { await handlePicked(newItem) }
        }
        .sheet(item: $playingItem) { item in
            mediaViewer(item)
        }
    }

    private func stageLabel(_ stage: UploadState.Stage) -> String {
        switch stage {
        case .compressing: return l10n.t("venueMedia.compressing")
        case .uploading: return String(format: l10n.t("venueMedia.uploading"), Int(uploadState.fraction * 100))
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

    private func handlePicked(_ pickerItem: PhotosPickerItem) async {
        uploadError = nil
        uploadState.fraction = 0
        defer {
            uploadState.stage = nil
            selectedPickerItem = nil
        }
        let isVideo = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }
        var tempFiles: [URL] = []
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        do {
            let fileURL: URL
            let contentType: String
            let fileExtension: String
            if isVideo {
                uploadState.stage = .compressing
                // FileRepresentation copies the movie to a temp file instead
                // of loading hundreds of MB into memory as Data.
                guard let picked = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
                    uploadError = l10n.t("venueMedia.error.load")
                    return
                }
                tempFiles.append(picked.url)
                fileURL = try await VideoCompressor.compress(picked.url, maxSeconds: Self.maxVideoSeconds)
                tempFiles.append(fileURL)
                contentType = "video/mp4"
                fileExtension = "mp4"
            } else {
                guard let data = try await pickerItem.loadTransferable(type: Data.self),
                      let jpeg = ImageDownscaler.jpeg(from: data, maxDimension: 1600) else {
                    uploadError = l10n.t("venueMedia.error.load")
                    return
                }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try jpeg.write(to: tmp)
                tempFiles.append(tmp)
                fileURL = tmp
                contentType = "image/jpeg"
                fileExtension = "jpg"
            }

            uploadState.stage = .uploading
            let state = uploadState
            let newItem = try await repo.upload(
                venueId: venue.id,
                fileURL: fileURL,
                mediaType: isVideo ? .video : .photo,
                contentType: contentType,
                fileExtension: fileExtension
            ) { fraction in
                state.fraction = fraction
            }
            withAnimation { items.insert(newItem, at: 0) }
            BPHaptics.success()
        } catch {
            uploadError = error.localizedDescription
            BPHaptics.error()
        }
    }
}

/// Main-actor progress holder — a @MainActor class is Sendable, so the
/// repository's @Sendable progress closure can capture it without dragging
/// the whole View struct across the actor boundary.
@MainActor
private final class UploadState: ObservableObject {
    enum Stage { case compressing, uploading }
    @Published var stage: Stage?
    @Published var fraction: Double = 0
}

/// Receives a picked movie as a file on disk (copied out of the Photos
/// sandbox) rather than as in-memory Data.
private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

enum VideoCompressor {
    /// 720p H.264 mp4, trimmed to `maxSeconds`. A 60s clip lands around
    /// 20-30MB — comfortably under Supabase's 50MB object cap, and ~10x
    /// smaller than what the camera wrote.
    static func compress(_ input: URL, maxSeconds: Double) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VenueMediaError.compressionFailed
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        export.shouldOptimizeForNetworkUse = true
        let duration = try await asset.load(.duration)
        if duration.seconds > maxSeconds {
            export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        }
        if #available(iOS 18, *) {
            try await export.export(to: output, as: .mp4)
        } else {
            try await legacyExport(export, to: output)
        }
        return output
    }

    @available(iOS, deprecated: 18.0)
    private static func legacyExport(_ export: AVAssetExportSession, to output: URL) async throws {
        export.outputURL = output
        export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else {
            throw export.error ?? VenueMediaError.compressionFailed
        }
    }
}

enum ImageDownscaler {
    /// Re-encodes any picked image (HEIC included) as a JPEG no larger than
    /// `maxDimension` on its long edge — a 48MP HEIC becomes ~400KB.
    static func jpeg(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}
