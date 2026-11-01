import AppKit
import Observation
import PhotoViewerCore

enum ViewMode: Equatable {
    case loupe
    case grid
    case compare
    case survey
}

struct ViewerError: Identifiable, LocalizedError {
    let id = UUID()
    let title: String
    let message: String

    var errorDescription: String? { message }
}

private struct DeletionUndo {
    let folderURL: URL
    let entries: [TrashResult]
    let marks: [String: ShotMark]
    let shotIDs: [String]
}

/// Owns the current folder, the visible (filtered) shots and the shown image.
@MainActor
@Observable
final class BrowserViewModel {
    private(set) var allShots: [Shot] = []
    private(set) var shots: [Shot] = []
    private(set) var currentIndex: Int = 0
    private(set) var currentImage: NSImage?
    private(set) var isLoading = false
    private(set) var isDeleting = false
    private(set) var folderURL: URL?
    private(set) var toast: String?
    private(set) var preferRAW = false
    private(set) var filter: ShotFilter = .all
    private(set) var marks: [String: ShotMark] = [:]
    private(set) var viewMode: ViewMode = .loupe
    private(set) var surveyStartIndex: Int = 0
    var isFilmstripExpanded = UserDefaults.standard.object(forKey: "filmstripExpanded") as? Bool ?? true
    var showDeleteRejectedConfirmation = false

    var error: ViewerError?

    private var lastDeletion: DeletionUndo?

    private let markStore: ShotMarkStore
    private var loadGeneration = 0
    private var toastTask: Task<Void, Never>?

    init(markStore: ShotMarkStore = ShotMarkStore()) {
        self.markStore = markStore
        self.marks = (try? markStore.load()) ?? [:]
    }

    // MARK: - Derived state

    var currentShot: Shot? {
        guard shots.indices.contains(currentIndex) else { return nil }
        return shots[currentIndex]
    }

    var currentPhoto: Photo? {
        currentShot?.photo(preferRAW: preferRAW)
    }

    var nextShot: Shot? {
        guard shots.indices.contains(currentIndex + 1) else { return nil }
        return shots[currentIndex + 1]
    }

    var surveyShots: [Shot] {
        guard !shots.isEmpty else { return [] }
        let start = min(max(surveyStartIndex, 0), max(0, shots.count - 1))
        let end = min(start + 4, shots.count)
        return Array(shots[start..<end])
    }

    var surveyActiveSlot: Int {
        guard !shots.isEmpty else { return 0 }
        return min(max(currentIndex - surveyStartIndex, 0), max(0, surveyShots.count - 1))
    }

    var canGoPrevious: Bool {
        !shots.isEmpty && currentIndex > 0
    }

    var canGoNext: Bool {
        !shots.isEmpty && currentIndex < shots.count - 1
    }

    var positionText: String {
        guard !shots.isEmpty else { return "0 / 0" }
        return "\(currentIndex + 1) / \(shots.count)"
    }

    var windowTitle: String {
        currentPhoto?.name ?? "PhotoViewer"
    }

    var canToggleFormat: Bool {
        currentShot?.hasPairedFormats == true
    }

    var formatLabel: String {
        guard let shot = currentShot else { return "" }
        if shot.hasPairedFormats {
            return preferRAW ? "NEF" : "JPG"
        }
        return shot.formatBadge
    }

    var pairBadge: String? {
        guard let shot = currentShot, shot.hasPairedFormats else { return nil }
        return shot.formatBadge
    }

    var hasAnyShots: Bool {
        !allShots.isEmpty
    }

    var isFilterEmpty: Bool {
        !allShots.isEmpty && shots.isEmpty
    }

    var rejectedShotCount: Int {
        count(for: .rejected)
    }

    var rejectedFileCount: Int {
        allShots.reduce(0) { partial, shot in
            partial + (mark(for: shot).flag == .reject ? shot.fileCount : 0)
        }
    }

    var canUndoDelete: Bool {
        lastDeletion != nil
    }

    var currentMark: ShotMark {
        guard let shot = currentShot else { return ShotMark() }
        return mark(for: shot)
    }

    var currentRating: Int {
        currentMark.rating
    }

    var currentFlag: ShotMark.Flag {
        currentMark.flag
    }

    func mark(for shot: Shot) -> ShotMark {
        marks[shot.id] ?? ShotMark()
    }

    func count(for filter: ShotFilter) -> Int {
        allShots.reduce(0) { partial, shot in
            partial + (filter.matches(mark(for: shot)) ? 1 : 0)
        }
    }

    // MARK: - Opening

    func openPanelForImage() {
        let panel = NSOpenPanel()
        panel.title = "打开图片"
        panel.message = "PhotoViewer 会自动加载这张图片所在的整个文件夹。"
        panel.prompt = "打开"
        panel.allowedContentTypes = ImageFormat.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let folderURL {
            panel.directoryURL = folderURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            Task { await open(url: url) }
        }
    }

    func openPanelForFolder() {
        let panel = NSOpenPanel()
        panel.title = "打开文件夹"
        panel.message = "选择包含图片的文件夹。"
        panel.prompt = "打开"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if let folderURL {
            panel.directoryURL = folderURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            Task { await open(url: url) }
        }
    }

    func open(url: URL) async {
        let url = url.standardizedFileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        do {
            if isDirectory {
                try await loadFolder(url, selecting: nil)
            } else {
                guard ImageFormat.isSupported(url) else {
                    throw ViewerError(
                        title: "不支持的图片格式",
                        message: "“\(url.lastPathComponent)”不是当前版本支持的图片格式。"
                    )
                }
                try await loadFolder(url.deletingLastPathComponent(), selecting: url)
            }
        } catch {
            present(error)
        }
    }

    func consumeOpenRequests() {
        let urls = OpenRequestCenter.shared.drain()
        guard let first = urls.first else { return }
        Task { await open(url: first) }
    }

    func handleDroppedURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        Task { await open(url: first) }
    }

    private func loadFolder(_ folder: URL, selecting target: URL?) async throws {
        let folderChanged = folderURL?.standardizedFileURL != folder.standardizedFileURL
        if folderChanged {
            ImageLoader.shared.clearAll()
            ThumbnailLoader.shared.clearAll()
            preferRAW = false
            filter = .all
        }
        viewMode = .loupe
        if let target {
            preferRAW = ImageFormat.isRAW(target)
            // Opening a specific file should always show it, even if a filter
            // was active from the previous folder.
            filter = .all
        }

        let scanned = try await Task.detached(priority: .userInitiated) {
            try FolderScanner().scanShots(folder)
        }.value

        let targetShot: Shot?
        if let target {
            targetShot = scanned.first { shot in
                shot.files.contains(where: { $0.url == target })
            }
            if targetShot == nil, !scanned.isEmpty {
                throw ViewerError(
                    title: "找不到这张图片",
                    message: "图片可能已被移动、删除，或所在文件夹无法读取。"
                )
            }
        } else {
            targetShot = nil
        }

        folderURL = folder
        allShots = scanned
        rebuildVisible(selecting: targetShot?.id, fallbackIndex: 0)

        guard !shots.isEmpty else {
            currentImage = nil
            isLoading = false
            return
        }

        loadCurrent()
    }

    // MARK: - Navigation

    func goPrevious() {
        guard !isDeleting, canGoPrevious else { return }
        currentIndex -= 1
        if viewMode == .survey { ensureSurveyWindow() }
        loadCurrent()
    }

    func goNext() {
        guard !isDeleting, canGoNext else { return }
        currentIndex += 1
        if viewMode == .survey { ensureSurveyWindow() }
        loadCurrent()
    }

    func select(index: Int) {
        guard shots.indices.contains(index), !isDeleting else { return }
        currentIndex = index
        loadCurrent()
    }

    func toggleGridView() {
        if viewMode == .grid {
            showLoupe()
        } else {
            viewMode = .grid
        }
    }

    func showLoupe() {
        guard viewMode != .loupe else { return }
        viewMode = .loupe
        loadCurrent()
    }

    func showCompare() {
        guard !shots.isEmpty else { return }
        viewMode = .compare
    }

    func toggleCompare() {
        if viewMode == .compare {
            showLoupe()
        } else {
            showCompare()
        }
    }

    func toggleFilmstrip() {
        isFilmstripExpanded.toggle()
        UserDefaults.standard.set(isFilmstripExpanded, forKey: "filmstripExpanded")
    }

    func showSurvey() {
        guard !shots.isEmpty else { return }
        viewMode = .survey
        surveyStartIndex = min(max(currentIndex, 0), max(0, shots.count - 4))
        ensureSurveyWindow()
    }

    func toggleSurvey() {
        if viewMode == .survey {
            showLoupe()
        } else {
            showSurvey()
        }
    }

    func selectSurveySlot(_ slot: Int) {
        let globalIndex = surveyStartIndex + slot
        guard shots.indices.contains(globalIndex) else { return }
        currentIndex = globalIndex
    }

    func toggleDisplayFormat() {
        guard let shot = currentShot else { return }
        guard shot.hasPairedFormats else {
            showToast("这张没有 NEF+JPG 配对")
            return
        }

        preferRAW.toggle()
        showToast(preferRAW ? "显示 RAW（NEF）" : "显示 JPEG")
        loadCurrent()
    }

    // MARK: - Filtering and marks

    func setFilter(_ newFilter: ShotFilter) {
        guard newFilter != filter else { return }

        let currentID = currentShot?.id
        let oldIndex = currentIndex
        filter = newFilter
        rebuildVisible(selecting: currentID, fallbackIndex: oldIndex)

        if shots.isEmpty {
            currentImage = nil
            isLoading = false
        } else {
            loadCurrent()
        }
    }

    func rate(_ rating: Int) {
        guard let shot = currentShot else { return }
        let oldIndex = currentIndex
        var mark = mark(for: shot)
        let value = min(max(rating, 0), 5)
        guard mark.rating != value else { return }

        mark.rating = value
        store(mark, for: shot)
        afterMarkChange(shotID: shot.id, oldIndex: oldIndex)
    }

    func clearRating() {
        rate(0)
    }

    func setFlag(_ flag: ShotMark.Flag) {
        guard let shot = currentShot else { return }
        let oldIndex = currentIndex
        var mark = mark(for: shot)
        guard mark.flag != flag else { return }

        mark.flag = flag
        store(mark, for: shot)
        afterMarkChange(shotID: shot.id, oldIndex: oldIndex)
    }

    func clearFlag() {
        setFlag(.none)
    }

    func toggleFlag(_ flag: ShotMark.Flag) {
        guard flag != .none else {
            clearFlag()
            return
        }
        if currentFlag == flag {
            clearFlag()
        } else {
            setFlag(flag)
        }
    }

    private var autoAdvanceAfterRating: Bool {
        UserDefaults.standard.object(forKey: "autoAdvanceAfterRating") as? Bool ?? true
    }

    private func store(_ mark: ShotMark, for shot: Shot) {
        if mark.rating == 0 && mark.flag == .none {
            marks.removeValue(forKey: shot.id)
        } else {
            marks[shot.id] = mark
        }
        saveMarks()
    }

    private func saveMarks() {
        do {
            try markStore.save(marks)
        } catch {
            self.error = ViewerError(
                title: "标记保存失败",
                message: error.localizedDescription
            )
        }
    }

    private func afterMarkChange(shotID: String, oldIndex: Int) {
        let autoAdvance = viewMode == .loupe && autoAdvanceAfterRating
        rebuildVisible(selecting: shotID, fallbackIndex: oldIndex)

        if let nextIndex = CullingMath.nextIndexAfterMark(
            shotID: shotID,
            visible: shots,
            oldIndex: oldIndex,
            autoAdvance: autoAdvance
        ) {
            currentIndex = nextIndex
        }

        if shots.isEmpty {
            currentImage = nil
            isLoading = false
        } else {
            loadCurrent()
        }
    }

    private func rebuildVisible(selecting shotID: String?, fallbackIndex: Int) {
        shots = allShots.filter { filter.matches(mark(for: $0)) }

        if let shotID, let index = shots.firstIndex(where: { $0.id == shotID }) {
            currentIndex = index
        } else {
            currentIndex = min(max(fallbackIndex, 0), max(0, shots.count - 1))
        }

        if viewMode == .survey {
            ensureSurveyWindow()
        }
    }

    private func ensureSurveyWindow() {
        guard !shots.isEmpty else {
            surveyStartIndex = 0
            return
        }

        if currentIndex < surveyStartIndex {
            surveyStartIndex = currentIndex
        }
        if currentIndex >= surveyStartIndex + 4 {
            surveyStartIndex = currentIndex - 3
        }
        surveyStartIndex = min(
            max(surveyStartIndex, 0),
            max(0, shots.count - 4)
        )
    }

    // MARK: - Image loading

    private func loadCurrent() {
        guard viewMode == .loupe else { return }
        guard let photo = currentPhoto else {
            currentImage = nil
            isLoading = false
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        ImageLoader.shared.clearFullImage()
        let maxPixel = ImageLoader.shared.fitPixelSize()

        var relevantURLs: Set<URL> = [photo.url]
        if currentIndex > 0 {
            relevantURLs.insert(shots[currentIndex - 1].photo(preferRAW: preferRAW).url)
        }
        if currentIndex + 1 < shots.count {
            relevantURLs.insert(shots[currentIndex + 1].photo(preferRAW: preferRAW).url)
        }
        ImageLoader.shared.cancelPending(keeping: relevantURLs, maxPixel: maxPixel)

        if let cached = ImageLoader.shared.cachedImage(for: photo.url, maxPixel: maxPixel) {
            currentImage = cached
            isLoading = false
            preloadNeighbors(maxPixel: maxPixel)
            return
        }

        // Black canvas + spinner is less confusing than leaving the wrong photo.
        currentImage = nil
        isLoading = true

        Task { [weak self] in
            guard let self else { return }
            let image = await ImageLoader.shared.load(url: photo.url, maxPixel: maxPixel)

            guard self.loadGeneration == generation,
                  self.currentPhoto?.url == photo.url
            else {
                return
            }

            if let image {
                self.currentImage = image
                self.isLoading = false
                self.preloadNeighbors(maxPixel: maxPixel)
            } else {
                self.currentImage = nil
                self.isLoading = false
                self.error = ViewerError(
                    title: "无法显示图片",
                    message: "无法解码“\(photo.name)”。文件可能已损坏，或格式暂不受支持。"
                )
            }
        }
    }

    private func preloadNeighbors(maxPixel: Int) {
        var urls: [URL] = []
        if currentIndex > 0 {
            urls.append(shots[currentIndex - 1].photo(preferRAW: preferRAW).url)
        }
        if currentIndex + 1 < shots.count {
            urls.append(shots[currentIndex + 1].photo(preferRAW: preferRAW).url)
        }
        ImageLoader.shared.preload(urls: urls, maxPixel: maxPixel)
    }

    // MARK: - Deleting

    func requestDelete() {
        guard let shot = currentShot, !isDeleting else { return }
        isDeleting = true
        Task { await delete(shot) }
    }

    private func delete(_ shot: Shot) async {
        defer { isDeleting = false }

        var results: [TrashResult] = []
        var failures: [String] = []
        let deletedMark = marks[shot.id]
        for file in shot.files {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try TrashService().moveToTrash(file.url)
                }.value
                results.append(result)
            } catch {
                failures.append("\(file.name)：\(error.localizedDescription)")
            }
            ImageLoader.shared.removeCached(url: file.url)
        }

        if !failures.isEmpty {
            await refreshShots(preserving: shot.id)
            present(
                ViewerError(
                    title: "删除未完成",
                    message: failures.joined(separator: "\n")
                )
            )
            return
        }

        if let folderURL {
            lastDeletion = DeletionUndo(
                folderURL: folderURL,
                entries: results,
                marks: deletedMark.map { [shot.id: $0] } ?? [:],
                shotIDs: [shot.id]
            )
        }

        guard let removedIndex = shots.firstIndex(where: { $0.id == shot.id }) else {
            return
        }

        let originalCount = shots.count
        shots.remove(at: removedIndex)
        allShots.removeAll { $0.id == shot.id }
        if marks.removeValue(forKey: shot.id) != nil {
            saveMarks()
        }
        loadGeneration += 1

        if let nextIndex = BrowserMath.indexAfterDeleting(index: removedIndex, count: originalCount) {
            currentIndex = nextIndex
            if viewMode == .survey { ensureSurveyWindow() }
            if shots.isEmpty {
                currentImage = nil
                isLoading = false
            } else {
                loadCurrent()
            }
        } else {
            currentIndex = 0
            currentImage = nil
            isLoading = false
            surveyStartIndex = 0
            ImageLoader.shared.cancelPending(
                keeping: [],
                maxPixel: ImageLoader.shared.fitPixelSize()
            )
        }

        let formatSuffix = shot.hasPairedFormats ? "（NEF+JPG）" : ""
        showToast("已移到废纸篓：\(shot.fileCount) 个文件\(formatSuffix)，⌘Z 撤销")
    }

    // MARK: - Batch deletion / undo

    func requestDeleteRejected() {
        guard rejectedShotCount > 0, !isDeleting else { return }
        showDeleteRejectedConfirmation = true
    }

    func deleteRejectedShots() async {
        guard !isDeleting, let folder = folderURL else { return }
        let rejected = allShots.filter { mark(for: $0).flag == .reject }
        guard !rejected.isEmpty else { return }

        isDeleting = true
        defer { isDeleting = false }

        var results: [TrashResult] = []
        var failures: [String] = []
        var deletedMarks: [String: ShotMark] = [:]

        for shot in rejected {
            if let mark = marks[shot.id] {
                deletedMarks[shot.id] = mark
            }
            for file in shot.files {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try TrashService().moveToTrash(file.url)
                    }.value
                    results.append(result)
                } catch {
                    failures.append("\(file.name)：\(error.localizedDescription)")
                }
                ImageLoader.shared.removeCached(url: file.url)
            }
        }

        if !failures.isEmpty {
            await refreshShots(preserving: currentShot?.id)
            present(
                ViewerError(
                    title: "批量删除未完成",
                    message: failures.joined(separator: "\n")
                )
            )
            return
        }

        lastDeletion = DeletionUndo(
            folderURL: folder,
            entries: results,
            marks: deletedMarks,
            shotIDs: rejected.map(\.id)
        )

        let currentID = currentShot?.id
        let oldIndex = currentIndex
        let ids = Set(rejected.map(\.id))
        allShots.removeAll { ids.contains($0.id) }
        for id in ids {
            marks.removeValue(forKey: id)
        }
        saveMarks()

        rebuildVisible(selecting: currentID, fallbackIndex: oldIndex)
        if shots.isEmpty {
            currentImage = nil
            isLoading = false
            ImageLoader.shared.cancelPending(
                keeping: [],
                maxPixel: ImageLoader.shared.fitPixelSize()
            )
        } else {
            loadCurrent()
        }

        showToast("已删除 \(rejected.count) 张废片（\(results.count) 个文件），⌘Z 撤销")
    }

    func undoLastDeletion() {
        guard let deletion = lastDeletion else {
            showToast("没有可撤销的删除")
            return
        }
        guard !isDeleting else { return }
        guard let folder = folderURL,
              folder.standardizedFileURL == deletion.folderURL.standardizedFileURL
        else {
            showToast("请回到原文件夹后再撤销")
            return
        }

        isDeleting = true
        Task { await performUndo(deletion) }
    }

    private func performUndo(_ deletion: DeletionUndo) async {
        defer { isDeleting = false }

        var failures: [String] = []
        for entry in deletion.entries {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try TrashService().restore(entry)
                }.value
            } catch {
                failures.append(
                    "\(entry.originalURL.lastPathComponent)：\(error.localizedDescription)"
                )
            }
        }

        guard let folder = folderURL else {
            lastDeletion = nil
            return
        }

        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try FolderScanner().scanShots(folder)
            }.value

            allShots = scanned
            for (id, mark) in deletion.marks where scanned.contains(where: { $0.id == id }) {
                marks[id] = mark
            }
            saveMarks()

            let restoredID = deletion.shotIDs.first { id in
                scanned.contains(where: { $0.id == id })
            }
            rebuildVisible(selecting: restoredID, fallbackIndex: currentIndex)

            if shots.isEmpty {
                currentImage = nil
                isLoading = false
                ImageLoader.shared.cancelPending(
                    keeping: [],
                    maxPixel: ImageLoader.shared.fitPixelSize()
                )
            } else {
                loadCurrent()
            }
        } catch {
            present(error)
        }

        lastDeletion = nil

        if failures.isEmpty {
            showToast("已撤销删除：\(deletion.shotIDs.count) 张照片")
        } else {
            present(
                ViewerError(
                    title: "撤销未完成",
                    message: failures.joined(separator: "\n")
                )
            )
        }
    }

    private func refreshShots(preserving shotID: String?) async {
        guard let folder = folderURL else { return }

        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try FolderScanner().scanShots(folder)
            }.value

            allShots = scanned
            let shotStillExists = shotID.map { id in
                scanned.contains(where: { $0.id == id })
            } ?? true

            if let shotID, !shotStillExists, marks.removeValue(forKey: shotID) != nil {
                saveMarks()
            }

            rebuildVisible(
                selecting: shotStillExists ? shotID : nil,
                fallbackIndex: currentIndex
            )

            if shots.isEmpty {
                currentImage = nil
                isLoading = false
                ImageLoader.shared.cancelPending(
                    keeping: [],
                    maxPixel: ImageLoader.shared.fitPixelSize()
                )
            } else {
                loadCurrent()
            }
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        if let viewerError = error as? ViewerError {
            self.error = viewerError
        } else {
            self.error = ViewerError(
                title: "操作失败",
                message: error.localizedDescription
            )
        }
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
