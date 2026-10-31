import PhotoViewerCore
import SwiftUI

struct Filmstrip: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        ScrollViewReader { proxy in
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
                .padding(.vertical, 7)
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
        }
        .frame(height: 72)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
