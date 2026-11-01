import PhotoViewerCore
import SwiftUI

/// Single compact app bar: open, position, filters, view mode, rating, flags.
struct TopBar: View {
    @Bindable var model: BrowserViewModel

    @State private var hoveredRating: Int?
    @State private var isHoveringClearRating = false
    @State private var isHoveringPick = false
    @State private var isHoveringReject = false

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 1000

            HStack(spacing: compact ? 5 : 8) {
                openMenu
                barDivider

                if model.hasAnyShots {
                    identity(compact: compact)
                    barDivider

                    if compact {
                        compactFilters
                    } else {
                        filters
                    }

                    Spacer(minLength: compact ? 4 : 8)

                    viewModeControl
                    barDivider
                    ratingControls(compact: compact)
                    flagControls(compact: compact)
                    moreMenu
                } else {
                    Text("打开图片或文件夹开始")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, 5)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var barDivider: some View {
        Divider()
            .frame(height: 16)
    }

    private var openMenu: some View {
        Menu {
            Button("打开图片…") {
                model.openPanelForImage()
            }
            Button("打开文件夹…") {
                model.openPanelForFolder()
            }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("打开图片或文件夹（⌘O / ⇧⌘O）")
    }

    private func identity(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            Text(model.positionText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()

            if !compact, let pairBadge = model.pairBadge {
                Text(pairBadge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if model.canToggleFormat {
                Button {
                    model.toggleDisplayFormat()
                } label: {
                    Text(model.formatLabel)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("切换 RAW / JPEG（J）")
            } else if !model.formatLabel.isEmpty {
                Text(model.formatLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize()
        .help(model.currentPhoto?.name ?? "未打开图片")
    }

    private var filters: some View {
        HStack(spacing: 4) {
            ForEach(ShotFilter.allCases) { filter in
                Button {
                    model.setFilter(filter)
                } label: {
                    HStack(spacing: 2) {
                        Text(shortTitle(for: filter))
                        Text("\(model.count(for: filter))")
                            .monospacedDigit()
                            .opacity(0.72)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(
                                model.filter == filter
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.10)
                            )
                    }
                    .foregroundStyle(model.filter == filter ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help("显示\(filter.title)")
            }
        }
        .fixedSize()
    }

    private var compactFilters: some View {
        Menu {
            ForEach(ShotFilter.allCases) { filter in
                Button {
                    model.setFilter(filter)
                } label: {
                    Text("\(filter.title)  \(model.count(for: filter))")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(model.filter.title)
                Text("\(model.count(for: model.filter))")
                    .monospacedDigit()
                    .opacity(0.72)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.8)
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("筛选照片")
    }

    private var viewModeControl: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    model.setViewMode(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.viewMode == mode ? Color.white : Color.secondary)
                        .frame(width: 26, height: 22)
                        .background {
                            if model.viewMode == mode {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
        .padding(2)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }

    private func ratingControls(compact: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    hoveredRating = nil
                    model.rate(value)
                } label: {
                    Image(systemName: value <= effectiveRating ? "star.fill" : "star")
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(
                            value <= effectiveRating
                                ? Color.yellow
                                : Color.secondary.opacity(hoveredRating == nil ? 1 : 0.55)
                        )
                        .frame(width: compact ? 18 : 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hoveredRating = value
                    } else if hoveredRating == value {
                        hoveredRating = nil
                    }
                }
                .help("\(value) 星")
            }

            Button {
                hoveredRating = nil
                isHoveringClearRating = false
                model.clearRating()
            } label: {
                Image(systemName: "star.slash")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(isHoveringClearRating ? Color.yellow : Color.secondary)
                    .frame(width: compact ? 18 : 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringClearRating = hovering
            }
            .help("清除星级（0）")
        }
        .disabled(model.currentShot == nil)
    }

    private func flagControls(compact: Bool) -> some View {
        HStack(spacing: 1) {
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(width: 1, height: 14)
                .padding(.horizontal, compact ? 2 : 3)

            Button {
                isHoveringPick = false
                model.toggleFlag(.pick)
            } label: {
                Image(systemName: model.currentFlag == .pick || isHoveringPick ? "flag.fill" : "flag")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(
                        model.currentFlag == .pick
                            ? Color.green
                            : (isHoveringPick ? Color.green.opacity(0.75) : Color.secondary)
                    )
                    .frame(width: compact ? 20 : 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringPick = hovering
            }
            .help("保留（P）")

            Button {
                isHoveringReject = false
                model.toggleFlag(.reject)
            } label: {
                Image(systemName: model.currentFlag == .reject || isHoveringReject ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(
                        model.currentFlag == .reject
                            ? Color.red
                            : (isHoveringReject ? Color.red.opacity(0.75) : Color.secondary)
                    )
                    .frame(width: compact ? 20 : 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringReject = hovering
            }
            .help("废片（X）")
        }
        .disabled(model.currentShot == nil)
    }

    private var moreMenu: some View {
        Menu {
            Button("删除当前照片…") {
                model.requestDelete()
            }
            .disabled(model.currentShot == nil || model.isDeleting)

            if model.rejectedShotCount > 0 {
                Button("删除所有废片…") {
                    model.requestDeleteRejected()
                }
                .disabled(model.isDeleting)
            }

            if model.canUndoDelete {
                Button("撤销最近删除") {
                    model.undoLastDeletion()
                }
                .disabled(model.isDeleting)
            }

            Divider()

            Button("全屏") {
                AppState.shared.toggleFullScreen()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多操作")
    }

    private var effectiveRating: Int {
        hoveredRating ?? model.currentRating
    }

    private func shortTitle(for filter: ShotFilter) -> String {
        switch filter {
        case .all: return "全部"
        case .unrated: return "未评"
        case .picked: return "保留"
        case .rejected: return "废片"
        }
    }
}
