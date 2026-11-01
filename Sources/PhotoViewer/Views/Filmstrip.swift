import PhotoViewerCore
import SwiftUI

struct Filmstrip: View {
    @Bindable var model: BrowserViewModel

    @State private var contentWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var isHoveringScrollbar = false
    @State private var isHoveringCollapseButton = false

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 6) {
                            ForEach(Array(model.shots.enumerated()), id: \.element.id) { index, shot in
                                Button {
                                    model.select(index: index)
                                } label: {
                                    ShotThumbnailView(
                                        shot: shot,
                                        size: 58,
                                        rating: model.mark(for: shot).rating,
                                        flag: model.mark(for: shot).flag,
                                        isSelected: index == model.currentIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(shot.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                    }
                    .frame(height: 74)
                    .onScrollGeometryChange(for: FilmstripScrollMetrics.self) { geometry in
                        FilmstripScrollMetrics(
                            offset: geometry.contentOffset.x,
                            contentWidth: geometry.contentSize.width,
                            viewportWidth: geometry.containerSize.width
                        )
                    } action: { _, metrics in
                        if abs(metrics.offset - scrollOffset) > 0.5 {
                            scrollOffset = metrics.offset
                        }
                        if abs(metrics.contentWidth - contentWidth) > 0.5 {
                            contentWidth = metrics.contentWidth
                        }
                        if abs(metrics.viewportWidth - viewportWidth) > 0.5 {
                            viewportWidth = metrics.viewportWidth
                        }
                    }
                    .onChange(of: model.currentShot?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let id = model.currentShot?.id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }

                    bottomBar(
                        viewportWidth: viewportWidth > 0 ? viewportWidth : outer.size.width,
                        proxy: proxy
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(height: 85)
        .background(.bar)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Divider()

                Button {
                    model.toggleFilmstrip()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isHoveringCollapseButton ? Color.primary : Color.secondary)
                        .frame(width: 48, height: 12)
                        .background(.bar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringCollapseButton = hovering
                }
                .help("折叠胶片条（T）")
            }
        }
    }

    @ViewBuilder
    private func bottomBar(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        scrollbar(
            viewportWidth: viewportWidth,
            trackWidth: max(0, viewportWidth - 20),
            proxy: proxy
        )
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func scrollbar(
        viewportWidth: CGFloat,
        trackWidth: CGFloat,
        proxy: ScrollViewProxy
    ) -> some View {
        let overflowing = contentWidth > viewportWidth + 1

        if overflowing, !model.shots.isEmpty, trackWidth > 0 {
            let visibleFraction = min(1, viewportWidth / max(contentWidth, 1))
            let thumbWidth = min(trackWidth, max(28, trackWidth * visibleFraction))
            let availableThumbTravel = max(1, trackWidth - thumbWidth)
            let maxOffset = max(1, contentWidth - viewportWidth)
            let progress = min(1, max(0, scrollOffset / maxOffset))
            let thumbOffset = availableThumbTravel * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.14))
                    .frame(width: trackWidth, height: 3)

                Capsule()
                    .fill(.primary.opacity(isHoveringScrollbar ? 0.70 : 0.46))
                    .frame(width: thumbWidth, height: 6)
                    .offset(x: thumbOffset)
            }
            .frame(width: trackWidth, height: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringScrollbar = hovering
            }
            .animation(.easeInOut(duration: 0.12), value: isHoveringScrollbar)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(
                            max((value.location.x - thumbWidth / 2) / availableThumbTravel, 0),
                            1
                        )
                        scroll(to: fraction, proxy: proxy)
                    }
            )
        } else {
            Color.clear
                .frame(width: trackWidth, height: 8)
        }
    }

    private func scroll(to fraction: CGFloat, proxy: ScrollViewProxy) {
        let count = model.shots.count
        guard count > 1 else { return }

        let index = min(
            count - 1,
            max(0, Int((fraction * CGFloat(count - 1)).rounded()))
        )
        proxy.scrollTo(model.shots[index].id, anchor: .center)
    }
}

private struct FilmstripScrollMetrics: Equatable {
    let offset: CGFloat
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
}
