import SwiftUI

struct EmptyStateView: View {
    let folderURL: URL?
    let isFilterEmpty: Bool
    let filterTitle: String
    let onShowAll: () -> Void
    let onOpenImage: () -> Void
    let onOpenFolder: () -> Void

    private var hasFolder: Bool { folderURL != nil }

    private var title: String {
        if isFilterEmpty {
            return "当前筛选下没有照片"
        }
        return hasFolder ? "这个文件夹里没有可显示的图片" : "打开一张图片开始浏览"
    }

    private var systemImage: String {
        if isFilterEmpty {
            return "line.3.horizontal.decrease.circle"
        }
        return hasFolder ? "photo.badge.exclamationmark" : "photo.on.rectangle.angled"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.55))

            Text(title)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)

            if isFilterEmpty {
                Text("「\(filterTitle)」中还没有照片，切回「全部」继续浏览。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
            } else if let folderURL {
                Text(folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("可以直接把图片或文件夹拖进窗口")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
            }

            HStack(spacing: 12) {
                if isFilterEmpty {
                    Button("显示全部", action: onShowAll)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("打开图片", action: onOpenImage)
                        .buttonStyle(.borderedProminent)
                }
                Button("打开文件夹", action: onOpenFolder)
                    .buttonStyle(.bordered)
            }

            Text("支持 NEF、JPEG、PNG、HEIC、TIFF、GIF、BMP、WebP")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
