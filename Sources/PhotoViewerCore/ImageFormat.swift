import Foundation
import UniformTypeIdentifiers

/// Formats the viewer can display.
///
/// Nikon NEF is supported through ImageIO; the Z30 files in the sample folder
/// decode correctly. RAW+JPEG pairs are grouped into a single `Shot`.
public enum ImageFormat {
    public static let jpegExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif"
    ]

    public static let rawExtensions: Set<String> = [
        "nef"
    ]

    public static let otherExtensions: Set<String> = [
        "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"
    ]

    public static let supportedExtensions: Set<String> =
        jpegExtensions.union(rawExtensions).union(otherExtensions)

    /// Used by `NSOpenPanel` and Finder open registration.
    public static let contentTypes: [UTType] = [
        .jpeg, .png, .heic, .heif, .tiff, .gif, .bmp, .webP
    ] + rawContentTypes

    public static let rawContentTypes: [UTType] = [
        UTType(filenameExtension: "nef")
    ].compactMap { $0 }

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isJPEG(_ url: URL) -> Bool {
        jpegExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isRAW(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased())
    }

    /// Compact label for badges: `JPG`, `NEF`, `PNG`.
    public static func shortName(for url: URL) -> String {
        isJPEG(url) ? "JPG" : displayName(for: url)
    }

    public static func displayName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "jpe", "jfif": return "JPEG"
        case "nef": return "NEF"
        case "png": return "PNG"
        case "heic": return "HEIC"
        case "heif": return "HEIF"
        case "tif", "tiff": return "TIFF"
        case "gif": return "GIF"
        case "bmp": return "BMP"
        case "webp": return "WebP"
        default: return ext.uppercased()
        }
    }
}
