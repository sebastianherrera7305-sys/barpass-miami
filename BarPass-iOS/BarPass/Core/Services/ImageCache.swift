import SwiftUI
import ImageIO

/// App-wide image cache with priority tiers. Map-marker logos and venue
/// preview images are the most-viewed assets, so they live in a `hot` cache
/// that is NOT discarded under memory pressure — returning to the map or
/// reopening a venue is instant. Everything else uses `standard`, which the
/// system may evict first. A large shared `URLCache` backs both on disk.
enum ImageCache {
    enum Priority { case hot, standard }

    // NSCache is documented thread-safe; safe to share across actors.
    nonisolated(unsafe) static let hot: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 200
        c.evictsObjectsWithDiscardedContent = false
        return c
    }()

    nonisolated(unsafe) static let standard: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 250
        return c
    }()

    /// Call once at launch.
    static func configure() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    static func image(for url: URL) -> UIImage? {
        hot.object(forKey: url as NSURL) ?? standard.object(forKey: url as NSURL)
    }

    static func store(_ img: UIImage, for url: URL, priority: Priority) {
        (priority == .hot ? hot : standard).setObject(img, forKey: url as NSURL)
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

        let maxPixel = max(targetSize?.width ?? 512, targetSize?.height ?? 512) * UIScreen.main.scale
        let opts: CFDictionary = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, opts),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts)
        else { return }

        let img = UIImage(cgImage: cgImage)
        ImageCache.store(img, for: url, priority: priority)
        if !Task.isCancelled { uiImage = img }
    }
}
