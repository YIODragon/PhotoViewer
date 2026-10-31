import Foundation

/// One logical photograph. A Nikon RAW+JPEG pair (`DSC_0001.NEF` +
/// `DSC_0001.JPG`) is one Shot, so the UI counts and deletes it as one item.
public struct Shot: Identifiable, Hashable, Sendable {
    public let id: String
    public let baseName: String
    public let files: [Photo]
    public let jpeg: Photo?
    public let raw: Photo?
    public let other: Photo?

    public init(files: [Photo]) {
        precondition(!files.isEmpty, "Shot requires at least one file")

        let sortedFiles = files.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.url.path < rhs.url.path
            }
            return comparison == .orderedAscending
        }

        self.files = sortedFiles
        self.baseName = sortedFiles[0].url.deletingPathExtension().lastPathComponent
        self.jpeg = sortedFiles.first { ImageFormat.isJPEG($0.url) }
        self.raw = sortedFiles.first { ImageFormat.isRAW($0.url) }
        self.other = sortedFiles.first {
            !ImageFormat.isJPEG($0.url) && !ImageFormat.isRAW($0.url)
        }

        let folderPath = sortedFiles[0].folder.standardizedFileURL.path
        self.id = "\(folderPath)|\(baseName.lowercased())"
    }

    /// Default display file: JPEG is faster; fall back to RAW or another format.
    public var primaryPhoto: Photo {
        jpeg ?? raw ?? files[0]
    }

    public func photo(preferRAW: Bool) -> Photo {
        if preferRAW, let raw {
            return raw
        }
        return jpeg ?? raw ?? files[0]
    }

    public var hasPairedFormats: Bool {
        jpeg != nil && raw != nil
    }

    public var isRawOnly: Bool {
        jpeg == nil && raw != nil
    }

    public var fileCount: Int {
        files.count
    }

    public var fileURLs: [URL] {
        files.map(\.url)
    }

    public var totalFileSize: Int64 {
        files.compactMap(\.fileSize).reduce(0, +)
    }

    /// Short label used by the toolbar: `NEF+JPG`, `NEF`, `JPG`, etc.
    public var formatBadge: String {
        if let jpeg, let raw {
            return "\(ImageFormat.shortName(for: raw.url))+\(ImageFormat.shortName(for: jpeg.url))"
        }
        if let raw {
            return ImageFormat.shortName(for: raw.url)
        }
        if let jpeg {
            return ImageFormat.shortName(for: jpeg.url)
        }
        if let other {
            return ImageFormat.shortName(for: other.url)
        }
        return ""
    }
}
