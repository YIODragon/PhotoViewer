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
            TopBar(model: model)

            ZStack {
                Color.black
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu {
                if model.currentShot != nil {
                    currentPhotoMenu
                }
            }

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
    private var currentPhotoMenu: some View {
        Button {
            model.goPrevious()
        } label: {
            Label("上一张", systemImage: "chevron.left")
        }
        .disabled(!model.canGoPrevious || model.isDeleting)

        Button {
            model.goNext()
        } label: {
            Label("下一张", systemImage: "chevron.right")
        }
        .disabled(!model.canGoNext || model.isDeleting)

        Divider()

        Menu("评分") {
            ForEach(0...5, id: \.self) { value in
                Button {
                    model.rate(value)
                } label: {
                    if value == 0 {
                        Text("清除星级")
                    } else {
                        Text(String(repeating: "★", count: value))
                    }
                }
            }
        }

        Button {
            model.toggleFlag(.pick)
        } label: {
            Label(
                model.currentFlag == .pick ? "取消保留" : "保留",
                systemImage: model.currentFlag == .pick ? "flag.fill" : "flag"
            )
        }

        Button {
            model.toggleFlag(.reject)
        } label: {
            Label(
                model.currentFlag == .reject ? "取消废片" : "标记废片",
                systemImage: model.currentFlag == .reject ? "xmark.circle.fill" : "xmark.circle"
            )
        }

        if model.currentFlag != .none {
            Button("取消旗标") {
                model.clearFlag()
            }
        }

        Divider()

        Menu("打开方式") {
            Button("默认应用") {
                model.openCurrentPhotoWithDefaultApplication()
            }

            let applications = model.currentPhotoApplications
            if !applications.isEmpty {
                Divider()
                ForEach(applications, id: \.self) { appURL in
                    Button {
                        model.openCurrentPhoto(with: appURL)
                    } label: {
                        Label {
                            Text(model.applicationName(for: appURL))
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        }
                    }
                }
            }

            Divider()

            Button("选择其他应用…") {
                model.chooseApplicationForCurrentPhoto()
            }
        }

        Button {
            model.revealCurrentPhotoInFinder()
        } label: {
            Label("在 Finder 中显示", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            model.requestDelete()
        } label: {
            Label("移到废纸篓", systemImage: "trash")
        }
        .disabled(model.isDeleting)
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
