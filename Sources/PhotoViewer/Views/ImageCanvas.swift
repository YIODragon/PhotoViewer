import AppKit
import Combine
import PhotoViewerCore
import SwiftUI

struct ImageCanvas: View {
    let photo: Photo
    let image: NSImage?
    let isLoading: Bool

    @State private var zoom = ZoomState()
    @State private var fullImage: NSImage?
    @State private var isLoadingFull = false
    @State private var fullTask: Task<Void, Never>?
    @State private var pinchStartScale: CGFloat?
    @State private var dragStartOffset: CGSize?
    @State private var hasAuthoritativeOriginalSize = false

    private var displayImage: NSImage? {
        fullImage ?? image
    }

    private var chrome: ChromeVisibility {
        AppState.shared.chrome
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let displayImage {
                    imageLayer(displayImage)
                } else if !isLoading {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32, weight: .light))
                        Text("无法显示这张图片")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .onHover { zoom.isHovering = $0 }
            .onAppear {
                zoom.updateViewport(geo.size)
                if !hasAuthoritativeOriginalSize, zoom.originalSize == .zero, let image {
                    zoom.setOriginalSize(image.size)
                }
                AppState.shared.activeZoom = zoom
            }
            .onChange(of: geo.size) { _, newSize in
                zoom.updateViewport(newSize)
            }
            .onChange(of: image?.size) { _, newSize in
                if !hasAuthoritativeOriginalSize, zoom.originalSize == .zero, let newSize {
                    zoom.setOriginalSize(newSize)
                }
                requestFullImageIfNeeded()
            }
            .onChange(of: zoom.currentScale) { _, _ in
                requestFullImageIfNeeded()
            }
            .overlay(alignment: .bottomTrailing) {
                if displayImage != nil {
                    zoomControls
                        .opacity(chrome.isVisible ? 1 : 0)
                        .allowsHitTesting(chrome.isVisible)
                        .onHover { hovering in
                            if hovering {
                                chrome.pointerEnteredControls()
                            } else {
                                chrome.pointerExitedControls()
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: chrome.isVisible)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                chrome.showTemporarily()
                zoom.zoomBy(1.25)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                chrome.showTemporarily()
                zoom.zoomBy(0.8)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
                chrome.showTemporarily()
                zoom.fit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomActualSize)) { _ in
                chrome.showTemporarily()
                zoom.actualSize()
            }
            .onChange(of: photo.id) { _, _ in
                // JPEG -> NEF (or the reverse) for the same shot: drop the old
                // full-resolution image but keep the current zoom state.
                fullImage = nil
                isLoadingFull = false
                hasAuthoritativeOriginalSize = false
                ImageLoader.shared.clearFullImage()
            }
            .task(id: photo.id) {
                await loadOriginalSize()
            }
            .onDisappear {
                fullTask?.cancel()
                if AppState.shared.activeZoom === zoom {
                    AppState.shared.activeZoom = nil
                }
            }
        }
    }

    private func imageLayer(_ image: NSImage) -> some View {
        let baseSize = zoom.originalSize.width > 0 ? zoom.originalSize : image.size
        let displaySize = CGSize(
            width: max(1, baseSize.width * zoom.currentScale),
            height: max(1, baseSize.height * zoom.currentScale)
        )

        return Image(nsImage: image)
            .resizable()
            .interpolation(zoom.currentScale > zoom.actualScale * 1.001 ? .none : .high)
            .frame(width: displaySize.width, height: displaySize.height)
            .offset(zoom.offset)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    chrome.showTemporarily()
                    zoom.toggleFitActual()
                }
            )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                chrome.showTemporarily()
                if dragStartOffset == nil {
                    dragStartOffset = zoom.offset
                }
                let start = dragStartOffset ?? .zero
                zoom.setOffset(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                chrome.showTemporarily()
                if pinchStartScale == nil {
                    pinchStartScale = zoom.currentScale
                }
                let start = pinchStartScale ?? zoom.currentScale
                zoom.setScale(start * value.magnification)
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            zoomButton(systemName: "minus", help: "缩小（⌘-）") {
                zoom.zoomBy(0.8)
            }

            if isLoadingFull {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: 44, height: 22)
            } else {
                Text("\(zoom.zoomPercent)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(minWidth: 44, minHeight: 22)
                    .help("100% = 1 个图片像素对应 1 个屏幕物理像素")
            }

            zoomButton(systemName: "plus", help: "放大（⌘+）") {
                zoom.zoomBy(1.25)
            }

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 14)

            zoomButton(systemName: "arrow.up.left.and.arrow.down.right", help: "适应窗口（⌘0）") {
                zoom.fit()
            }

            Button {
                chrome.showTemporarily()
                zoom.actualSize()
            } label: {
                Text("1:1")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("原始比例 100%（⌘1）")
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .padding(18)
    }

    private func zoomButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            chrome.showTemporarily()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func loadOriginalSize() async {
        let url = photo.url
        let size = await Task.detached(priority: .userInitiated) {
            ImageDecoder.orientedPixelSize(at: url)
        }.value

        guard !Task.isCancelled, photo.url == url else { return }
        if let size {
            zoom.setOriginalSize(size)
            hasAuthoritativeOriginalSize = true
            requestFullImageIfNeeded()
        }
    }

    private func requestFullImageIfNeeded() {
        guard fullImage == nil, !isLoadingFull, let image else { return }
        guard zoom.originalSize.width > 0, zoom.originalSize.height > 0 else { return }

        let displayedWidth = zoom.originalSize.width * zoom.currentScale * zoom.backingScale
        let displayedHeight = zoom.originalSize.height * zoom.currentScale * zoom.backingScale
        let needsMoreDetail = displayedWidth > image.size.width * 1.05
            || displayedHeight > image.size.height * 1.05
        guard needsMoreDetail else { return }

        isLoadingFull = true
        let url = photo.url
        fullTask = Task {
            let loaded = await ImageLoader.shared.loadFull(url: url)
            guard !Task.isCancelled, photo.url == url else { return }
            if let loaded {
                fullImage = loaded
            }
            isLoadingFull = false
        }
    }
}

