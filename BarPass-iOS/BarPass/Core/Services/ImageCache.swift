import SwiftUI
import ImageIO
import UIKit

/// App-wide image cache with priority tiers. Map-marker logos and venue
/// preview images are the most-viewed assets, so they live in a `hot` cache.
/// Everything else uses `standard`, which gets purged on memory pressure.
/// A large shared `URLCache` backs both on disk.
enum ImageCache {
    enum Priority { case hot, standard }

    private static let mb = 1024 * 1024

    // NSCache is documented thread-safe; safe to share across actors.
    nonisolated(unsafe) static let hot: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 100
        c.totalCostLimit = 120 * mb
        return c
    }()

    nonisolated(unsafe) static let standard: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 150
        c.totalCostLimit = 80 * mb
        return c
    }()

    /// Call once at launch.
    static func configure() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            standard.removeAllObjects()
            hot.removeAllObjects()
        }
    }

    static func image(for url: URL) -> UIImage? {
        hot.object(forKey: url as NSURL) ?? standard.object(forKey: url as NSURL)
    }

    static func store(_ img: UIImage, for url: URL, priority: Priority) {
        let pixelW = img.size.width * img.scale
        let pixelH = img.size.height * img.scale
        let cost = Int(pixelW * pixelH * 4)
        (priority == .hot ? hot : standard).setObject(img, forKey: url as NSURL, cost: cost)
    }

    /// Downsamples raw image bytes (a locally-picked photo, e.g. from
    /// PhotosPicker) via ImageIO instead of decoding full-resolution —
    /// `UIImage(data:)` on a 12MP+ camera photo decodes tens of MB into
    /// memory for what's usually a ~150pt preview. Same technique
    /// `CachedImage` already uses for network images.
    static func downsampled(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let opts: CFDictionary = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, opts),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Same as `downsampled(from:maxPixel:)` but reads from disk without
    /// loading the whole file into a `Data` first — used for cover images
    /// re-read from `Application Support` on every render.
    static func downsampled(contentsOf fileURL: URL, maxPixel: CGFloat) -> UIImage? {
        let opts: CFDictionary = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Drop-in cached image with downsampling. `.task(id:)` cancels the load
/// automatically when the view leaves the hierarchy or the URL changes — so
/// off-screen markers/cells don't keep downloading. Pass `.hot` for markers
/// and venue previews.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize?
    var priority: ImageCache.Priority = .standard
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.image(for: url) { uiImage = cached; return }

        // View.task runs on the MainActor — decoding there freezes the whole
        // UI (the login was untouchable while 181 hidden cards loaded). All
        // network + decode now happens on a detached background task.
        let maxPixel = min(max(targetSize?.width ?? 512, targetSize?.height ?? 512) * UIScreen.main.scale, 1536)
        let prio = priority
        let img = await Task.detached(priority: .utility) { () -> UIImage? in
            // URLSession respeta URLCache.shared (disco, 256MB) — antes se
            // usaba CGImageSourceCreateWithURL, que baja la imagen con su
            // propia red por afuera de URLCache y nunca persistía nada:
            // cada apertura de la app volvía a descargar TODAS las
            // imágenes de cero, sin importar lo ya cacheado.
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            let opts: CFDictionary = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, opts),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts)
            else { return nil }
            return UIImage(cgImage: cg)
        }.value

        guard let img else { return }
        ImageCache.store(img, for: url, priority: prio)
        if !Task.isCancelled { uiImage = img }
    }
}
