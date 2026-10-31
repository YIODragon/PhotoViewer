import AppKit
import Observation

/// Pure zoom/pan geometry, kept out of the SwiftUI view so it can be checked
/// without a window.
///
/// `100%` means one image pixel maps to one physical display pixel. On a Retina
/// screen that is `1 / backingScale` points per image pixel, not 1 point.
@MainActor
@Observable
public final class ZoomState {
    public enum Mode: Equatable {
        case fit
        case actual
        case custom
    }

    public var mode: Mode = .fit
    public var customScale: CGFloat = 1
    public var offset: CGSize = .zero
    public var viewport: CGSize = .zero
    public var originalSize: CGSize = .zero
    public var isHovering = false
    public let backingScale: CGFloat
    public let padding: CGFloat

    public init(
        backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2,
        padding: CGFloat = 32
    ) {
        self.backingScale = max(backingScale, 1)
        self.padding = padding
    }

    public var actualScale: CGFloat {
        1 / backingScale
    }

    public var fitScale: CGFloat {
        guard viewport.width > padding,
              viewport.height > padding,
              originalSize.width > 0,
              originalSize.height > 0
        else {
            return actualScale
        }

        let widthScale = (viewport.width - padding) / originalSize.width
        let heightScale = (viewport.height - padding) / originalSize.height
        let computed = min(widthScale, heightScale)
        // Don't enlarge a small image past 100% just to fill the window.
        return min(max(computed, 0.0001), actualScale)
    }

    public var minScale: CGFloat {
        max(0.0001, fitScale * 0.25)
    }

    public var maxScale: CGFloat {
        max(actualScale, fitScale) * 8
    }

    public var currentScale: CGFloat {
        switch mode {
        case .fit:
            return fitScale
        case .actual:
            return actualScale
        case .custom:
            return min(max(customScale, minScale), maxScale)
        }
    }

    public var zoomPercent: Int {
        Int((currentScale / actualScale * 100).rounded())
    }

    public var isZoomed: Bool {
        currentScale > fitScale + 0.0001
    }

    public func updateViewport(_ size: CGSize) {
        viewport = size
        if mode == .fit {
            offset = .zero
        }
        clampOffset()
    }

    public func setOriginalSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        originalSize = size
        if mode == .fit {
            offset = .zero
        }
        clampOffset()
    }

    public func fit() {
        mode = .fit
        offset = .zero
    }

    public func actualSize() {
        mode = .actual
        offset = .zero
        clampOffset()
    }

    public func toggleFitActual() {
        if mode == .fit {
            actualSize()
        } else {
            fit()
        }
    }

    public func zoomBy(_ factor: CGFloat) {
        guard factor > 0 else { return }
        mode = .custom
        customScale = min(max(currentScale * factor, minScale), maxScale)
        clampOffset()
    }

    public func setScale(_ newScale: CGFloat) {
        mode = .custom
        customScale = min(max(newScale, minScale), maxScale)
        clampOffset()
    }

    public func panBy(_ translation: CGSize) {
        offset.width += translation.width
        offset.height += translation.height
        clampOffset()
    }

    public func setOffset(_ newOffset: CGSize) {
        offset = newOffset
        clampOffset()
    }

    public func clampOffset() {
        guard originalSize.width > 0, originalSize.height > 0 else {
            offset = .zero
            return
        }

        let displayWidth = originalSize.width * currentScale
        let displayHeight = originalSize.height * currentScale
        let availableWidth = max(0, viewport.width - padding)
        let availableHeight = max(0, viewport.height - padding)
        let maxX = max(0, (displayWidth - availableWidth) / 2)
        let maxY = max(0, (displayHeight - availableHeight) / 2)

        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }
}
