import AppKit
import Combine
import PhotoViewerCore
import SwiftUI

/// Two-up compare: current shot on the left, next visible shot on the right.
/// Zoom and pan are shared, so checking focus on a burst stays aligned.
struct CompareView: View {
    @Bindable var model: BrowserViewModel

    @State private var zoomFactor: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var pinchStartFactor: CGFloat?
    @State private var dragStartOffset: CGSize?
    @State private var leftPixelSize: CGSize = .zero
    @State private var paneSize: CGSize = .zero

    private var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    var body: some View {
        GeometryReader { geo in
            let contentSize = CGSize(
                width: max(1, (geo.size.width - 1) / 2),
                height: geo.size.height
            )

            HStack(spacing: 0) {
                if let shot = model.currentShot, let photo = model.currentPhoto {
                    ComparePane(
                        shot: shot,
                        photo: photo,
                        title: "当前",
                        isRight: false,
                        zoomFactor: zoomFactor,
                        panOffset: panOffset,
                        rating: model.currentRating,
                        flag: model.currentFlag,
                        onActivate: nil
                    )
                } else {
                    placeholder("没有照片")
                }

                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1)

                if let next = model.nextShot {
                    ComparePane(
                        shot: next,
                        photo: next.photo(preferRAW: model.preferRAW),
                        title: "下一张",
                        isRight: true,
                        zoomFactor: zoomFactor,
                        panOffset: panOffset,
                        rating: model.mark(for: next).rating,
                        flag: model.mark(for: next).flag,
                        onActivate: { model.goNext() }
                    )
                } else {
                    placeholder("已经是最后一张")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(paneSize: contentSize))
            .simultaneousGesture(magnifyGesture(paneSize: contentSize))
            .overlay(alignment: .bottomTrailing) {
                zoomControls(paneSize: contentSize)
            }
            .onAppear {
                paneSize = contentSize
                clampPan()
            }
            .onChange(of: geo.size) { _, newSize in
                paneSize = CGSize(
                    width: max(1, (newSize.width - 1) / 2),
                    height: newSize.height
                )
                clampPan()
            }
            .onChange(of: model.currentPhoto?.url) { _, _ in
                panOffset = .zero
                clampPan()
            }
            .task(id: model.currentPhoto?.url) {
                await loadLeftPixelSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
                fit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomActualSize)) { _ in
                actualSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                adjustZoom(by: 1.25)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                adjustZoom(by: 0.8)
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareZoomToggle)) { _ in
                toggleZoom()
            }
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1.slash")
                .font(.system(size: 36, weight: .light))
            Text(message)
                .font(.callout)
        }
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func dragGesture(paneSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard zoomFactor > 1.001 else { return }
                if dragStartOffset == nil {
                    dragStartOffset = panOffset
                }
                let start = dragStartOffset ?? .zero
                panOffset = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                clampPan()
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    private func magnifyGesture(paneSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartFactor == nil {
                    pinchStartFactor = zoomFactor
                }
                let start = pinchStartFactor ?? zoomFactor
                zoomFactor = min(max(start * value.magnification, 1), 8)
                clampPan()
            }
            .onEnded { _ in
                pinchStartFactor = nil
            }
    }

    private var zoomPercent: Int {
        let factor = actualSizeFactor()
        guard factor > 0 else { return Int((zoomFactor * 100).rounded()) }
        return Int((zoomFactor / factor * 100).rounded())
    }

    private func zoomControls(paneSize: CGSize) -> some View {
        HStack(spacing: 2) {
            Button {
                adjustZoom(by: 0.8)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("缩小")

            Text("\(zoomPercent)%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 42, minHeight: 22)
                .help("相对于 1:1 的缩放")

            Button {
                adjustZoom(by: 1.25)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("放大")

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 14)

            Button {
                fit()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("适应窗口（⌘0）")

            Button {
                actualSize()
            } label: {
                Text("1:1")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("原始比例（⌘1）")
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .padding(18)
    }

    private func adjustZoom(by factor: CGFloat) {
        zoomFactor = min(max(zoomFactor * factor, 1), 8)
        clampPan()
    }

    private func fit() {
        zoomFactor = 1
        panOffset = .zero
    }

    private func actualSize() {
        zoomFactor = max(1, min(8, actualSizeFactor()))
        panOffset = .zero
        clampPan()
    }

    private func toggleZoom() {
        if abs(zoomFactor - actualSizeFactor()) < 0.02 {
            fit()
        } else {
            actualSize()
        }
    }

    private func actualSizeFactor() -> CGFloat {
        let fit = leftFitScale()
        guard fit > 0 else { return 1 }
        return max(1, min(8, (1 / backingScale) / fit))
    }

    private func leftFitScale() -> CGFloat {
        guard leftPixelSize.width > 0,
              leftPixelSize.height > 0,
              paneSize.width > 24,
              paneSize.height > 24
        else {
            return 1
        }
        return min(
            (paneSize.width - 24) / leftPixelSize.width,
            (paneSize.height - 24) / leftPixelSize.height
        )
    }

    private func clampPan() {
        let maxX = max(0, paneSize.width * (zoomFactor - 1) / 2)
        let maxY = max(0, paneSize.height * (zoomFactor - 1) / 2)
        panOffset.width = min(max(panOffset.width, -maxX), maxX)
        panOffset.height = min(max(panOffset.height, -maxY), maxY)
    }

    private func loadLeftPixelSize() async {
        guard let url = model.currentPhoto?.url else {
            leftPixelSize = .zero
            return
        }
        let size = await Task.detached(priority: .userInitiated) {
            ImageDecoder.orientedPixelSize(at: url)
        }.value
        guard !Task.isCancelled, model.currentPhoto?.url == url else { return }
        leftPixelSize = size ?? .zero
        clampPan()
    }
}
