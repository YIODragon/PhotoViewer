import Foundation

public struct TrashResult: Sendable {
    public let originalURL: URL
    public let trashedURL: URL?

    public init(originalURL: URL, trashedURL: URL?) {
        self.originalURL = originalURL
        self.trashedURL = trashedURL
    }
}

public enum TrashServiceError: LocalizedError, Sendable {
    case failed(url: URL, reason: String)
    case restoreFailed(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .failed(let url, let reason):
            return "无法将“\(url.lastPathComponent)”移到废纸篓：\(reason)"
        case .restoreFailed(let url, let reason):
            return "无法恢复“\(url.lastPathComponent)”：\(reason)"
        }
    }

    public var recoverySuggestion: String? {
        "请确认文件没有被其他程序占用，并且你对所在文件夹有写入权限。"
    }
}

/// The only deletion path in the app. Files always go to the macOS Trash first.
public struct TrashService: Sendable {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> TrashResult {
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            let nsError = error as NSError
            throw TrashServiceError.failed(
                url: url,
                reason: "\(error.localizedDescription)（\(nsError.domain) \(nsError.code)）"
            )
        }
        return TrashResult(originalURL: url, trashedURL: resultingURL as URL?)
    }

    /// Moves a file back from the Trash. Used by undo.
    public func restore(_ result: TrashResult) throws {
        guard let trashedURL = result.trashedURL else {
            throw TrashServiceError.restoreFailed(
                url: result.originalURL,
                reason: "废纸篓中找不到对应的文件。"
            )
        }
        guard FileManager.default.fileExists(atPath: trashedURL.path) else {
            throw TrashServiceError.restoreFailed(
                url: result.originalURL,
                reason: "文件已不在废纸篓中，可能已被清空。"
            )
        }
        guard !FileManager.default.fileExists(atPath: result.originalURL.path) else {
            throw TrashServiceError.restoreFailed(
                url: result.originalURL,
                reason: "原位置已有同名文件。"
            )
        }

        do {
            try FileManager.default.moveItem(at: trashedURL, to: result.originalURL)
        } catch {
            let nsError = error as NSError
            throw TrashServiceError.restoreFailed(
                url: result.originalURL,
                reason: "\(error.localizedDescription)（\(nsError.domain) \(nsError.code)）"
            )
        }
    }
}
