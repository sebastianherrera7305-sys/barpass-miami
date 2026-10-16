import Foundation
import ImageIO

/// Forensic-grade metadata stripping para fotos de posts.
///
/// `ImageDownscaler.jpeg(from:maxDimension:)` ya re-encodea vía UIKit y
/// pierde EXIF/GPS en la práctica, pero no es auditable: UIKit es libre
/// de preservar Orientation u otros tags "cosméticos" en versiones
/// futuras. Para posts (que son contenido social con una expectativa de
/// privacidad explícita del owner) escribimos el JPEG directo con
/// `CGImageDestination` + properties `{}`, dejando CERO metadata.
///
/// Verificable con `exiftool out.jpg` → "ExifToolVersion: XX.X" + "File
/// Modification Date/Time" (los dos del propio exiftool) y nada más.
enum PostImageProcessor {

    /// Decodifica una imagen de cualquier formato soportado por iOS
    /// (HEIC, JPEG, PNG, WebP), la re-escala para que el lado largo
    /// quepa en `maxDimension`, y la re-encoda como JPEG sin metadata.
    ///
    /// Devuelve `nil` si el blob no es decodable como imagen — un
    /// cliente comprometido podría pasar bytes basura; mejor fallar en
    /// el cliente que al servidor con un 500.
    static func stripAndEncode(
        _ data: Data,
        maxDimension: CGFloat = 1600,
        quality: CGFloat = 0.82
    ) -> Data? {
        // 1. Decode source. ImageIO acepta HEIC/JPEG/PNG/WebP de iOS.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // 2. Thumbnail at target size — ImageIO respeta orientación al
        //    generar el thumbnail (lo "cocina" en los píxeles) y nos
        //    devuelve el CGImage ya rotado, sin necesidad de carry el
        //    tag Orientation adelante.
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
            return nil
        }

        // 3. Re-encode a JPEG con properties = empty dict → cero
        //    EXIF, cero GPS, cero IPTC, cero XMP, cero MakerNote. El
        //    compression quality va aparte en kCGImageDestinationLossyCompressionQuality.
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else { return nil }

        let destProps: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            // CRÍTICO: NO poner kCGImagePropertyExifDictionary,
            // kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
            // kCGImagePropertyTIFFDictionary. Al no pasarlos, el JPEG
            // sale desnudo.
        ]
        CGImageDestinationAddImage(dest, cg, destProps as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        return out as Data
    }
}

