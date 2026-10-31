import AppKit
import PhotoViewerCore
import SwiftUI

struct ComparePane: View {
    let shot: Shot
    let photo: Photo
    let title: String
    let isRight: Bool
    let zoomFactor: CGFloat
    let panOffset: CGSize
    let rating: Int
    let flag: ShotMark.Flag
    let onActivate: (() -> Void)?
    let loadFullResolution: Bool

    @State private var fitImage: NSImage?
    @State private var fullImage: NSImage?
    @State private var originalSize: CGSize = .zero
    @State private var failed = false
    @State private var isLoadingFull = false
    @State private var fullTask: Task<Void, Never>?
    @State private var loadGeneration = 0

    init(
        shot: Shot,
        photo: Photo,
        title: String,
        isRight: Bool,
        zoomFactor: CGFloat,
        panOffset: CGSize,
        rating: Int,
        flag: ShotMark.Flag,
        onActivate: (() -> Void)?,
        loadFullResolution: Bool = true
    ) {
        self.shot = shot
        self.photo = photo
        self.title = title
        self.isRight = isRight
        self.zoomFactor = zoomFactor
        self.panOffset = panOffset
        self.rating = rating
        self.flag = flag
        self.onActivate = onActivate
        self.loadFullResolution = loadFullResolution
    }

    private var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let image = fullImage ?? fitImage {
                    imageLayer(image, viewport: geo.size)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22, weight: .light))
                        Text("无法显示")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                overlays
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
            }
            .task(id: photo.url) {
                await load(viewport: geo.size)
            }
            .onChange(of: zoomFactor) { _, _ in
                requestFullImage(viewport: geo.size, generation: loadGeneration)
            }
            .onChange(of: geo.size) { _, newSize in
                requestFullImage(viewport: newSize, generation: loadGeneration)
            }
            .onDisappear {
                fullTask?.cancel()
            }
        }
    }

    private func imageLayer(_ image: NSImage, viewport: CGSize) -> some View {
        let baseSize = originalSize.width > 0 ? originalSize : image.size
        let scale = fitScale(for: baseSize, in: viewport) * zoomFactor
        let displaySize = CGSize(
            width: max(1, baseSize.width * scale),
            height: max(1, baseSize.height * scale)
        )

        return Image(nsImage: image)
            .resizable()
            .interpolation(scale > (1 / backingScale) * 1.001 ? .none : .high)
            .frame(width: displaySize.width, height: displaySize.height)
            .offset(panOffset)
    }

    private var overlays: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(shot.baseName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                if isLoadingFull {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(8)
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                HStack(spacing: 6) {
                    if rating > 0 {
                        Text("★\(rating)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.yellow)
                    }
                    if flag == .pick {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if flag == .reject {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.42), in: Capsule())

                Spacer()

                if isRight {
                    Text("点击设为当前")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.42), in: Capsule())
                }
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func load(viewport: CGSize) async {
        loadGeneration += 1
        let generation = loadGeneration
        fullTask?.cancel()
        fitImage = nil
        fullImage = nil
        originalSize = .zero
        failed = false
        isLoadingFull = false

        let url = photo.url
        let image = await ImageLoader.shared.load(
            url: url,
            maxPixel: ImageLoader.shared.fitPixelSize()
        )
        guard !Task.isCancelled, generation == loadGeneration else { return }

        fitImage = image
        failed = image == nil

        if let size = await Task.detached(priority: .userInitiated, operation: {
            ImageDecoder.orientedPixelSize(at: url)
        }).value {
            originalSize = size
        } else if let image {
            originalSize = image.size
        }

        requestFullImage(viewport: viewport, generation: generation)
    }

    private func fitScale(for size: CGSize, in viewport: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0,
              viewport.width > 24, viewport.height > 24
        else {
            return 1
        }
        return min(
            (viewport.width - 24) / size.width,
            (viewport.height - 24) / size.height
        )
    }

    private func requestFullImage(viewport: CGSize, generation: Int) {
        guard loadFullResolution,
              generation == loadGeneration,
              fullImage == nil,
              !isLoadingFull,
              let fitImage
        else {
            return
        }

        let baseSize = originalSize.width > 0 ? originalSize : fitImage.size
        let scale = fitScale(for: baseSize, in: viewport) * zoomFactor
        let displayedWidth = baseSize.width * scale * backingScale
        let displayedHeight = baseSize.height * scale * backingScale
        let needsMoreDetail = displayedWidth > fitImage.size.width * 1.05
            || displayedHeight > fitImage.size.height * 1.05
        guard needsMoreDetail else { return }

        isLoadingFull = true
        let url = photo.url
        let maxPixel = min(max(Int(baseSize.width), Int(baseSize.height)), 8192)
        fullTask = Task {
            let cgImage = await Task.detached(priority: .userInitiated) {
                ImageDecoder.downsampledImage(at: url, maxPixel: maxPixel)
            }.value

            guard !Task.isCancelled,
                  generation == loadGeneration,
                  let cgImage
            else {
                isLoadingFull = false
                return
            }

            fullImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            isLoadingFull = false
        }
    }
}
