import AppKit
import CoreGraphics

/// Small thumbnail cache for the filmstrip and grid. Kept separate from the
/// main image cache so browsing a large folder cannot evict the current image.
@MainActor
public final class ThumbnailLoader {
    public static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var tasks: [String: Task<CGImage?, Never>] = [:]

    private init() {
        cache.countLimit = 1500
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    public func load(url: URL, size: Int) async -> NSImage? {
        let target = max(32, size)
        let key = cacheKey(url, target)

        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let task: Task<CGImage?, Never>
        if let existing = tasks[key] {
            task = existing
        } else {
            let newTask = Task.detached(priority: .utility) {
                ImageDecoder.downsampledImage(at: url, maxPixel: target)
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

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return image
    }

    public func clearAll() {
        cache.removeAllObjects()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func cacheKey(_ url: URL, _ size: Int) -> String {
        "\(url.path)|\(size)"
    }
}
