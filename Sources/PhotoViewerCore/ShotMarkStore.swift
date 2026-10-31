import Foundation

/// Reads and writes the local culling database. The store is deliberately tiny:
/// a JSON dictionary keyed by `Shot.id`.
public struct ShotMarkStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
    }

    public func load() throws -> [String: ShotMark] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: ShotMark].self, from: data)
    }

    public func save(_ marks: [String: ShotMark]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(marks)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var defaultURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("PhotoViewer", isDirectory: true)
            .appendingPathComponent("marks.json")
    }
}
