import AppKit
import Combine
import PhotoViewerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: BrowserViewModel
    @State private var isDropTargeted = false

    private var chrome: ChromeVisibility {
        AppState.shared.chrome
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.hasAnyShots {
                FilterBar(model: model)
            }

            ZStack {
                Color.black
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.viewMode == .loupe && !model.shots.isEmpty {
                if model.isFilmstripExpanded {
                    Filmstrip(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    CollapsedFilmstripBar(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: model.isFilmstripExpanded)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                chrome.mouseMoved(to: location)
            case .ended:
                chrome.mouseExited()
            }
        }
        .onAppear {
            chrome.showTemporarily()
        }
        .onChange(of: model.currentPhoto?.id) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                chrome.showTemporarily()
            }
        }
        .navigationTitle(model.windowTitle)
        .toolbar { toolbarContent }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.toast)
        .alert(item: $model.error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "删除所有废片？",
            isPresented: $model.showDeleteRejectedConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "删除 \(model.rejectedShotCount) 张（\(model.rejectedFileCount) 个文件）",
                role: .destructive
            ) {
                Task { await model.deleteRejectedShots() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("整对 NEF+JPG 会移到废纸篓；删除后可按 ⌘Z 撤销。")
        }
        .background(WindowAccessor())
        .onChange(of: model.windowTitle) { _, newTitle in
            AppState.shared.mainWindow?.title = newTitle
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRequestsAvailable)) { _ in
            model.consumeOpenRequests()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.shots.isEmpty {
            emptyState
        } else if model.viewMode == .grid {
            PhotoGrid(model: model)
        } else if model.viewMode == .compare {
            CompareView(model: model)
        } else if model.viewMode == .survey {
            SurveyView(model: model)
        } else if let shot = model.currentShot, let photo = model.currentPhoto {
            ImageCanvas(photo: photo, image: model.currentImage, isLoading: model.isLoading)
                .id(shot.id)
                .overlay(alignment: .leading) {
                    EdgeNavigationButton(
                        systemName: "chevron.left",
                        help: "上一张（←）",
                        isEnabled: model.canGoPrevious && !model.isDeleting,
                        action: model.goPrevious
                    )
                    .padding(.leading, 18)
                    .opacity(chrome.isVisible ? 1 : 0)
                    .allowsHitTesting(chrome.isVisible)
                    .onHover { hovering in
                        if hovering {
                            chrome.pointerEnteredControls()
                        } else {
                            chrome.pointerExitedControls()
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: chrome.isVisible)
                }
                .overlay(alignment: .trailing) {
                    EdgeNavigationButton(
                        systemName: "chevron.right",
                        help: "下一张（→）",
                        isEnabled: model.canGoNext && !model.isDeleting,
                        action: model.goNext
                    )
                    .padding(.trailing, 18)
                    .opacity(chrome.isVisible ? 1 : 0)
                    .allowsHitTesting(chrome.isVisible)
                    .onHover { hovering in
                        if hovering {
                            chrome.pointerEnteredControls()
                        } else {
                            chrome.pointerExitedControls()
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: chrome.isVisible)
                }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            folderURL: model.folderURL,
            isFilterEmpty: model.isFilterEmpty,
            filterTitle: model.filter.title,
            onShowAll: { model.setFilter(.all) },
            onOpenImage: model.openPanelForImage,
            onOpenFolder: model.openPanelForFolder
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.openPanelForImage()
            } label: {
                Label("打开图片", systemImage: "photo")
            }
            .help("打开图片（⌘O）")

            Button {
                model.openPanelForFolder()
            } label: {
                Label("打开文件夹", systemImage: "folder")
            }
            .help("打开文件夹（⇧⌘O）")

            Divider()

            Button {
                model.goPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoPrevious)
            .help("上一张（←）")

            Button {
                model.goNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoNext)
            .help("下一张（→）")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 7) {
                Text(model.positionText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let pairBadge = model.pairBadge {
                    Text(pairBadge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if model.canToggleFormat {
                    Button {
                        model.toggleDisplayFormat()
                    } label: {
                        Text(model.formatLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("切换 RAW / JPEG（J）")
                } else if !model.formatLabel.isEmpty {
                    Text(model.formatLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .help(model.currentPhoto?.name ?? "未打开图片")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.requestDelete()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model.currentShot == nil || model.isDeleting)
            .help("删除整张（NEF+JPG 会一起删除，Delete）")

            Button {
                AppState.shared.toggleFullScreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("全屏（F / ⇧⌘F）")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let nsURL = object as? NSURL else { return }
            let url = nsURL as URL
            Task { @MainActor in
                OpenRequestCenter.shared.enqueue([url])
            }
        }
        return true
    }
}
