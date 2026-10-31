import Foundation

public enum FolderScannerError: LocalizedError, Sendable {
    case notDirectory(URL)
    case cannotRead(URL, String)

    public var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "“\(url.lastPathComponent)”不是文件夹。"
        case .cannotRead(let url, let message):
            return "无法读取文件夹“\(url.lastPathComponent)”：\(message)"
        }
    }
}

/// Scans one folder (non-recursive) for images we can display.
public struct FolderScanner: Sendable {
    public init() {}

    public func scan(_ folder: URL) throws -> [Photo] {
        let folder = folder.standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .contentModificationDateKey
        ]

        let folderValues = try? folder.resourceValues(forKeys: [.isDirectoryKey])
        guard folderValues?.isDirectory == true else {
            throw FolderScannerError.notDirectory(folder)
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            throw FolderScannerError.cannotRead(folder, error.localizedDescription)
        }

        var photos: [Photo] = []
        photos.reserveCapacity(urls.count)

        for url in urls where ImageFormat.isSupported(url) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }
            if values?.isSymbolicLink == true { continue }

            photos.append(
                Photo(
                    url: url.standardizedFileURL,
                    fileSize: values?.fileSize.map(Int64.init),
                    modificationDate: values?.contentModificationDate
                )
            )
        }

        // Finder-style natural ordering: IMG_1, IMG_2, IMG_10.
        photos.sort { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.url.path < rhs.url.path
            }
            return comparison == .orderedAscending
        }

        return photos
    }

    /// Groups files into logical shots. Nikon `DSC_0001.NEF` + `DSC_0001.JPG`
    /// become one shot; a RAW-only or JPEG-only file remains one shot.
    public func scanShots(_ folder: URL) throws -> [Shot] {
        let photos = try scan(folder)
        let groups = Dictionary(grouping: photos) { photo in
            photo.url.deletingPathExtension().lastPathComponent.lowercased()
        }

        var shots = groups.values.map { Shot(files: $0) }
        shots.sort { lhs, rhs in
            let comparison = lhs.baseName.localizedStandardCompare(rhs.baseName)
            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return comparison == .orderedAscending
        }
        return shots
    }
}

/// Small, testable index rules used after a deletion.
public enum BrowserMath {
    /// Returns the index that should be selected after removing `index`
    /// from a list that had `count` items.
    ///
    /// - If the deleted item was the last one, select the previous item.
    /// - Otherwise the following item shifts into the same index.
    /// - Returns nil when the folder becomes empty.
    public static func indexAfterDeleting(index: Int, count: Int) -> Int? {
        guard count > 1, index >= 0, index < count else { return nil }
        return min(index, count - 2)
    }
}
