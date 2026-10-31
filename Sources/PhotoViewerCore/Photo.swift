import Foundation

/// A single image file discovered in a folder.
public struct Photo: Identifiable, Hashable, Sendable {
    public let url: URL
    public let fileSize: Int64?
    public let modificationDate: Date?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var folder: URL { url.deletingLastPathComponent() }

    public init(url: URL, fileSize: Int64? = nil, modificationDate: Date? = nil) {
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public var formattedSize: String {
        guard let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
