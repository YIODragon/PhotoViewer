import AppKit
import CoreGraphics
import ImageIO

/// Stateless ImageIO helpers. Keeping decoding out of the cache makes it easy to
/// test and guarantees that no original file is ever modified.
public enum ImageDecoder {
    public static func downsampledImage(at url: URL, maxPixel: Int) -> CGImage? {
        guard maxPixel > 0 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // honor EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func pixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    /// Pixel dimensions after applying EXIF orientation. This is the coordinate
    /// system used by the zoom math, so portrait photos fit correctly.
    public static func orientedPixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }
}

/// Decodes images off the main thread and keeps a small LRU-ish cache.
///
/// The normal cache holds downsampled "fit" images plus two neighbours. A single
/// full-resolution image is loaded on demand when the user zooms in.
@MainActor
public final class ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var tasks: [String: Task<CGImage?, Never>] = [:]
    private var fullImage: NSImage?
    private var fullURL: URL?
    private var fullTask: Task<CGImage?, Never>?
    private var fullGeneration = 0

    private init() {
        cache.countLimit = 8
        cache.totalCostLimit = 192 * 1024 * 1024
    }

    /// Pixel size that is sufficient for the current screen at fit-to-window scale.
    public func fitPixelSize() -> Int {
        let screen = NSScreen.main
        let points = screen?.frame.width ?? 1440
        let scale = screen?.backingScaleFactor ?? 2
        return max(1600, min(4096, Int(points * scale)))
    }

    public func cachedImage(for url: URL, maxPixel: Int) -> NSImage? {
        cache.object(forKey: cacheKey(url, maxPixel) as NSString)
    }

    public func load(url: URL, maxPixel: Int) async -> NSImage? {
        let key = cacheKey(url, maxPixel)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let task: Task<CGImage?, Never>
        if let existing = tasks[key] {
            task = existing
        } else {
            let newTask = Task.detached(priority: .userInitiated) {
                ImageDecoder.downsampledImage(at: url, maxPixel: maxPixel)
            }
            tasks[key] = newTask
            task = newTask
        }

        let cgImage = await task.value
        tasks[key] = nil

        guard let cgImage else { return nil }

        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = cgImage.bytesPerRow * cgImage.height
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    /// Loads a single high-resolution image for zooming. Only one is retained so
    /// a 6000px photo does not multiply memory usage across the folder.
    public func loadFull(url: URL) async -> NSImage? {
        if fullURL == url, let fullImage {
            return fullImage
        }

        fullGeneration += 1
        let generation = fullGeneration
        fullTask?.cancel()
        fullImage = nil
        fullURL = nil

        guard let size = ImageDecoder.orientedPixelSize(at: url) else {
            return nil
        }

        let maxPixel = min(max(Int(size.width), Int(size.height)), 8192)
        let task = Task.detached(priority: .userInitiated) {
            ImageDecoder.downsampledImage(at: url, maxPixel: maxPixel)
        }
        fullTask = task

        let cgImage = await task.value
        guard generation == fullGeneration,
              !Task.isCancelled,
              let cgImage
        else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        fullImage = image
        fullURL = url
        fullTask = nil
        return image
    }

    public func clearFullImage() {
        fullGeneration += 1
        fullTask?.cancel()
        fullTask = nil
        fullImage = nil
        fullURL = nil
    }

    /// Warms the cache for the images on either side of the current one.
    public func preload(urls: [URL], maxPixel: Int) {
        for url in urls {
            let key = cacheKey(url, maxPixel)
            guard cache.object(forKey: key as NSString) == nil, tasks[key] == nil else { continue }

            let task = Task.detached(priority: .utility) {
                ImageDecoder.downsampledImage(at: url, maxPixel: maxPixel)
            }
            tasks[key] = task

            Task { @MainActor [weak self] in
                let cgImage = await task.value
                guard let self, let cgImage else { return }
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                self.cache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: cgImage.bytesPerRow * cgImage.height
                )
            }
        }
    }

    /// Cancels work for images that are no longer current or adjacent.
    public func cancelPending(keeping urls: Set<URL>, maxPixel: Int) {
        let keepKeys = Set(urls.map { cacheKey($0, maxPixel) })
        let keysToCancel = tasks.keys.filter { !keepKeys.contains($0) }
        for key in keysToCancel {
            tasks[key]?.cancel()
            tasks[key] = nil
        }
    }

    public func removeCached(url: URL) {
        cache.removeObject(forKey: cacheKey(url, fitPixelSize()) as NSString)
        if fullURL == url {
            clearFullImage()
        }
    }

    /// Drops everything when switching to a different folder so memory does not
    /// accumulate across folders.
    public func clearAll() {
        cache.removeAllObjects()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        clearFullImage()
    }

    private func cacheKey(_ url: URL, _ maxPixel: Int) -> String {
        "\(url.path)|\(maxPixel)"
    }
}
