import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// The one upload pipeline for user photos/videos — shared by the venue
/// page's "Fotos y videos" section and the post-check-in moment sheet, so
/// both go through the same compression (720p / 60s video, 1600px JPEG) and
/// the same resumable chunked upload. Extracted 2026-09-08: the feature
/// existed for two days and produced two photos total, both uploaded the
/// afternoon AFTER the night out — the button lived at the bottom of a long
/// venue page. The habit has to start at the moment of check-in.
@MainActor
final class VenueMediaUploader: ObservableObject {
    enum Stage { case compressing, uploading }
    @Published var stage: Stage?
    @Published var fraction: Double = 0
    @Published var error: String?
    /// The file is compressed, saved outside the temp directory and on the
    /// queue — it is NOT on the venue page yet. Views must say exactly that:
    /// a green "posted!" would be a lie and a red error would be one too,
    /// since this will be retried on its own.
    @Published var queuedForLater = false

    /// Longer clips are trimmed to this before upload — keeps a 720p clip
    /// around 20-30MB, under Supabase's 50MB object cap with room to spare.
    static let maxVideoSeconds: Double = 60

    private let repo: VenueMediaRepository

    init(repo: VenueMediaRepository = RepositoryDependencies.venueMedia) {
        self.repo = repo
    }

    var isBusy: Bool { stage != nil }

    func stageLabel(_ l10n: L10n) -> String? {
        switch stage {
        case .compressing: return l10n.t("venueMedia.compressing")
        case .uploading: return String(format: l10n.t("venueMedia.uploading"), Int(fraction * 100))
        case nil: return nil
        }
    }

    /// Compresses and uploads one picked item. Returns the stored row on
    /// success; on failure sets `error` (the server's own text when it has
    /// one) and returns nil. Never throws — callers just react to the result.
    func upload(_ pickerItem: PhotosPickerItem, venueId: String) async -> VenueMediaItem? {
        error = nil
        queuedForLater = false
        fraction = 0
        defer { stage = nil }
        let isVideo = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }
        var tempFiles: [URL] = []
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        // Hoisted out of the `do` so the catch below can still see what was
        // compressed and hand it to the queue. Nil means we never got as far
        // as a usable file — that IS a real error worth showing.
        var prepared: (url: URL, contentType: String, fileExtension: String)?
        do {
            let fileURL: URL
            let contentType: String
            let fileExtension: String
            if isVideo {
                stage = .compressing
                // FileRepresentation copies the movie to a temp file instead
                // of loading hundreds of MB into memory as Data.
                guard let picked = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
                    error = L10n.shared.t("venueMedia.error.load")
                    return nil
                }
                tempFiles.append(picked.url)
                fileURL = try await VideoCompressor.compress(picked.url, maxSeconds: Self.maxVideoSeconds)
                tempFiles.append(fileURL)
                contentType = "video/mp4"
                fileExtension = "mp4"
            } else {
                guard let data = try await pickerItem.loadTransferable(type: Data.self),
                      let jpeg = ImageDownscaler.jpeg(from: data, maxDimension: 1600) else {
                    error = L10n.shared.t("venueMedia.error.load")
                    return nil
                }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try jpeg.write(to: tmp)
                tempFiles.append(tmp)
                fileURL = tmp
                contentType = "image/jpeg"
                fileExtension = "jpg"
            }

            prepared = (fileURL, contentType, fileExtension)

            stage = .uploading
            let item = try await repo.upload(
                venueId: venueId,
                fileURL: fileURL,
                mediaType: isVideo ? .video : .photo,
                contentType: contentType,
                fileExtension: fileExtension
            ) { [weak self] fraction in
                self?.fraction = fraction
            }
            BPHaptics.success()
            return item
        } catch {
            // Venue LTE dropped the upload. The compressed file lives in the
            // temp directory, which iOS purges whenever it likes, so copy it
            // into the queue's own directory before the `defer` above deletes
            // it — then the queue re-uploads on reconnect, foreground or the
            // next launch. Only a file we could never even prepare (or could
            // not copy) is reported to the user as a failure.
            if let prepared,
               let fileName = try? OfflineQueue.stageMedia(prepared.url, fileExtension: prepared.fileExtension) {
                OfflineQueue.shared.enqueue(.venueMedia, [
                    "venueId": venueId,
                    "fileName": fileName,
                    "mediaType": (isVideo ? VenueMediaType.video : .photo).rawValue,
                    "contentType": prepared.contentType,
                    "fileExtension": prepared.fileExtension,
                ])
                queuedForLater = true
                BPHaptics.medium()
            } else {
                self.error = error.localizedDescription
                BPHaptics.error()
            }
            return nil
        }
    }
}

/// Receives a picked movie as a file on disk (copied out of the Photos
/// sandbox) rather than as in-memory Data.
struct PickedVideo: Transferable {
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
