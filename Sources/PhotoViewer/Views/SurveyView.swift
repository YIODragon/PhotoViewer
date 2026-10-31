import AppKit
import Combine
import PhotoViewerCore
import SwiftUI

/// Four-up survey around the current shot. Clicking a pane makes it current
/// without reflowing the four-shot window; arrows move through the folder.
struct SurveyView: View {
    @Bindable var model: BrowserViewModel

    @State private var zoomFactor: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var pinchStartFactor: CGFloat?
    @State private var dragStartOffset: CGSize?
    @State private var activePixelSize: CGSize = .zero
    @State private var paneSize: CGSize = .zero

    private var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    var body: some View {
        GeometryReader { geo in
            let contentSize = CGSize(
                width: max(1, (geo.size.width - 1) / 2),
                height: max(1, (geo.size.height - 1) / 2)
            )

            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    pane(0)
                    pane(1)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 1) {
                    pane(2)
                    pane(3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .overlay(alignment: .bottomTrailing) {
                zoomControls
            }
            .onAppear {
                paneSize = contentSize
                clampPan()
            }
            .onChange(of: geo.size) { _, newSize in
                paneSize = CGSize(
                    width: max(1, (newSize.width - 1) / 2),
                    height: max(1, (newSize.height - 1) / 2)
                )
                clampPan()
            }
            .onChange(of: model.currentPhoto?.url) { _, _ in
                panOffset = .zero
                clampPan()
            }
            .task(id: model.currentPhoto?.url) {
                await loadActivePixelSize()
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

    @ViewBuilder
    private func pane(_ slot: Int) -> some View {
        if model.surveyShots.indices.contains(slot) {
            let shot = model.surveyShots[slot]
            ComparePane(
                shot: shot,
                photo: shot.photo(preferRAW: model.preferRAW),
                title: "\(slot + 1)",
                isRight: false,
                zoomFactor: zoomFactor,
                panOffset: panOffset,
                rating: model.mark(for: shot).rating,
                flag: model.mark(for: shot).flag,
                onActivate: { model.selectSurveySlot(slot) },
                loadFullResolution: false
            )
            .overlay {
                if slot == model.surveyActiveSlot {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
        } else {
            placeholder("—")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 24, weight: .light))
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.35))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var dragGesture: some Gesture {
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

    private var magnifyGesture: some Gesture {
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

    private var zoomControls: some View {
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
            .help("原始比例（⌘1，Survey 中为预览比例）")
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
        guard activePixelSize.width > 0,
              activePixelSize.height > 0,
              paneSize.width > 24,
              paneSize.height > 24
        else {
            return 1
        }
        let fit = min(
            (paneSize.width - 24) / activePixelSize.width,
            (paneSize.height - 24) / activePixelSize.height
        )
        guard fit > 0 else { return 1 }
        return max(1, min(8, (1 / backingScale) / fit))
    }

    private func clampPan() {
        let maxX = max(0, paneSize.width * (zoomFactor - 1) / 2)
        let maxY = max(0, paneSize.height * (zoomFactor - 1) / 2)
        panOffset.width = min(max(panOffset.width, -maxX), maxX)
        panOffset.height = min(max(panOffset.height, -maxY), maxY)
    }

    private func loadActivePixelSize() async {
        guard let url = model.currentPhoto?.url else {
            activePixelSize = .zero
            return
        }
        let size = await Task.detached(priority: .userInitiated) {
            ImageDecoder.orientedPixelSize(at: url)
        }.value
        guard !Task.isCancelled, model.currentPhoto?.url == url else { return }
        activePixelSize = size ?? .zero
        clampPan()
    }
}
