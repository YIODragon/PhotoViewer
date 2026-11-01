import AppKit
import PhotoViewerCore
import SwiftUI

struct ShotThumbnailView: View {
    let shot: Shot
    let size: CGFloat
    let rating: Int
    let flag: ShotMark.Flag
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var failed = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.24, weight: .light))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack {
                HStack {
                    if flag == .pick {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if flag == .reject {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }

                Spacer()

                HStack {
                    if rating > 0 {
                        Text("★\(rating)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                }
            }
            .padding(4)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) {
            if flag != .none {
                Rectangle()
                    .fill(flag == .pick ? Color.green : Color.red)
                    .frame(width: 3)
                    .padding(.vertical, 3)
                    .padding(.leading, 1)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor
                        : (isHovering ? Color.white.opacity(0.28) : Color.white.opacity(0.08)),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: shot.primaryPhoto.url) {
            image = nil
            failed = false
            image = await ThumbnailLoader.shared.load(
                url: shot.primaryPhoto.url,
                size: Int(size * 2)
            )
            failed = image == nil
        }
        .help("\(shot.baseName)  \(shot.formatBadge)")
    }
}
