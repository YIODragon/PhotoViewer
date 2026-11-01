import PhotoViewerCore
import SwiftUI

/// Lightroom-style filter strip: counts, filtering and quick rating controls.
struct FilterBar: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ShotFilter.allCases) { filter in
                Button {
                    model.setFilter(filter)
                } label: {
                    HStack(spacing: 3) {
                        Text(filter.title)
                        Text("\(model.count(for: filter))")
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(
                                model.filter == filter
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12)
                            )
                    }
                    .foregroundStyle(model.filter == filter ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help("显示\(filter.title)")
            }

            if model.rejectedShotCount > 0 {
                Button {
                    model.requestDeleteRejected()
                } label: {
                    Label("删除废片 \(model.rejectedShotCount)", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("删除所有废片（\(model.rejectedFileCount) 个文件）")
                .disabled(model.isDeleting)
            }

            if model.canUndoDelete {
                Button {
                    model.undoLastDeletion()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("撤销删除（⌘Z）")
                .disabled(model.isDeleting)
            }

            Spacer(minLength: 10)

            ratingControls

            if model.viewMode == .loupe {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)

                Button {
                    model.toggleFilmstrip()
                } label: {
                    Image(systemName: model.isFilmstripExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(model.isFilmstripExpanded ? "折叠胶片条（T）" : "展开胶片条（T）")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var ratingControls: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    model.rate(value)
                } label: {
                    Image(systemName: value <= model.currentRating ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            value <= model.currentRating ? Color.yellow : Color.secondary
                        )
                        .frame(width: 16, height: 18)
                }
                .buttonStyle(.plain)
                .help("\(value) 星")
            }

            Button {
                model.clearRating()
            } label: {
                Image(systemName: "star.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .help("清除星级（0）")

            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 4)

            Button {
                model.toggleFlag(.pick)
            } label: {
                Image(systemName: model.currentFlag == .pick ? "flag.fill" : "flag")
                    .font(.system(size: 11))
                    .foregroundStyle(model.currentFlag == .pick ? Color.green : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("保留（P）")

            Button {
                model.toggleFlag(.reject)
            } label: {
                Image(systemName: model.currentFlag == .reject ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(model.currentFlag == .reject ? Color.red : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("废片（X）")
        }
        .disabled(model.currentShot == nil)
    }
}
