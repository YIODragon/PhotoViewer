import PhotoViewerCore
import SwiftUI

struct PhotoGrid: View {
    @Bindable var model: BrowserViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 10)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(model.shots.enumerated()), id: \.element.id) { index, shot in
                        Button {
                            model.select(index: index)
                        } label: {
                            ShotThumbnailView(
                                shot: shot,
                                size: 150,
                                rating: model.mark(for: shot).rating,
                                flag: model.mark(for: shot).flag,
                                isSelected: index == model.currentIndex
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                model.select(index: index)
                                model.showLoupe()
                            }
                        )
                        .help("单击选择，双击打开")
                        .id(shot.id)
                    }
                }
                .padding(12)
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
        .background(Color.black)
    }
}
